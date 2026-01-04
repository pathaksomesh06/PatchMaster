//
//  AppScanner.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

class AppScanner {
    static func scanInstalledApps() -> [InstalledApp] {
        // Force clear all caches
        clearLaunchServicesCache()
        
        // Wait for cache clear
        Thread.sleep(forTimeInterval: 2.0)
        
        let searchRoots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "~/Applications".expandingTildeInPath,
            "/Applications/Setapp",
            "/Library/Applications"
        ]
        
        var appsByBundle: [String: InstalledApp] = [:]
        for root in searchRoots {
            scanApps(at: root, maxDepth: 3, accumulator: &appsByBundle)
        }
        
        let uniqueApps = Array(appsByBundle.values)
        print("Found \(uniqueApps.count) unique apps after deduplication across \(searchRoots.count) roots")
        return uniqueApps
    }
    
    static func clearLaunchServicesCache() {
        print("🔄 Clearing Launch Services and Spotlight caches...")
        
        // Clear caches WITHOUT killing Dock/Finder (causes system instability)
        // NOTE: We do NOT use lsregister -kill as it causes Dock to restart/flicker
        let commands = [
            ["/usr/bin/killall", "cfprefsd"],
            // Just re-register apps without killing the database
            ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-R", "/Applications"],
            ["/usr/bin/touch", "/Applications"]
        ]
        
        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        // Force NSWorkspace refresh
        NSWorkspace.shared.noteFileSystemChanged("/Applications")
        Thread.sleep(forTimeInterval: 0.5)
        
        print("✅ Caches cleared")
    }
    
    private static func scanApps(at rootPath: String, maxDepth: Int, accumulator: inout [String: InstalledApp]) {
        let fm = FileManager.default
        let expandedPath = rootPath.expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expandedPath)
        
        guard fm.fileExists(atPath: expandedPath) else {
            print("⏭️ Skipping missing path: \(expandedPath)")
            return
        }
        
        let rootComponents = rootURL.pathComponents.count
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        
        if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: options, errorHandler: { url, error in
            print("⚠️ Enumerator error at \(url.path): \(error.localizedDescription)")
            return true
        }) {
            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - rootComponents
                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                
                guard url.pathExtension.lowercased() == "app" else { continue }
                if let app = getAppInfo(at: url.path) {
                    add(app, to: &accumulator)
                }
                enumerator.skipDescendants()
            }
        }
    }

    private static func add(_ app: InstalledApp, to accumulator: inout [String: InstalledApp]) {
        if let existing = accumulator[app.bundleId] {
            if VersionCompare.isNewer(app.version, than: existing.version) {
                accumulator[app.bundleId] = app
            }
        } else {
            accumulator[app.bundleId] = app
        }
    }
    
    private static func getAppInfo(at path: String) -> InstalledApp? {
        let plistPath = "\(path)/Contents/Info.plist"
        
        // Force reload plist from disk
        guard let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleId = plist["CFBundleIdentifier"] as? String else {
            return nil
        }
        
        // Extract both version strings
        let shortVersion = plist["CFBundleShortVersionString"] as? String
        let bundleVersion = plist["CFBundleVersion"] as? String
        
        // Select version: prefer longer/more detailed version to match update sources
        let version: String
        if bundleId == "com.google.android.studio", let short = shortVersion {
            version = short
        } else if bundleId == "com.github.GitHubClient" {
            version = shortVersion ?? bundleVersion ?? "0.0.0"
        } else if bundleId == "com.microsoft.PowerShell" {
            version = shortVersion ?? bundleVersion ?? "0.0.0"
        } else if let short = shortVersion, let bundle = bundleVersion {
            // General rule: use whichever has more components or is longer
            let shortParts = short.split(separator: ".")
            let bundleParts = bundle.split(separator: ".")
            
            if bundleParts.count > shortParts.count {
                version = bundle
            } else if shortParts.count > bundleParts.count {
                version = short
            } else {
                // Same component count: pick the longer string (handles cases like .0002 vs .2)
                version = bundle.count >= short.count ? bundle : short
            }
        } else if let short = shortVersion {
            version = short
        } else if let bundle = bundleVersion {
            version = bundle
        } else {
            version = (plist["CFBundleGetInfoString"] as? String)?.components(separatedBy: " ").first ?? "0.0.0"
        }
        
        // Clean version string
        let cleanVersion = version
            .replacingOccurrences(of: "Build ", with: "")
            .replacingOccurrences(of: "v", with: "")
            .replacingOccurrences(of: "V", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let icon = extractAppIcon(from: path, plist: plist as NSDictionary)
        return InstalledApp(bundleId: bundleId, version: cleanVersion, path: path, icon: icon)
    }
    
    private static func extractAppIcon(from appPath: String, plist: NSDictionary) -> NSImage? {
        // Primary: Use workspace icon
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        if icon.size.width > 0 && icon.size.height > 0 {
            return icon
        }
        
        // Fallback: Extract from bundle
        var iconFileName: String?
        
        if let iconFile = plist["CFBundleIconFile"] as? String {
            iconFileName = iconFile
        } else if let iconDict = plist["CFBundleIcons"] as? [String: Any],
                  let primaryIcon = iconDict["CFBundlePrimaryIcon"] as? [String: Any],
                  let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                  let firstIcon = iconFiles.first {
            iconFileName = firstIcon
        }
        
        if let iconFile = iconFileName {
            let resourcesPath = "\(appPath)/Contents/Resources"
            let possiblePaths = [
                "\(resourcesPath)/\(iconFile).icns",
                "\(resourcesPath)/\(iconFile)",
                "\(resourcesPath)/AppIcon.icns",
                "\(resourcesPath)/app.icns"
            ]
            
            for iconPath in possiblePaths {
                if FileManager.default.fileExists(atPath: iconPath) {
                    return NSImage(contentsOfFile: iconPath)
                }
            }
        }
        
        return nil
    }
}

extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}
