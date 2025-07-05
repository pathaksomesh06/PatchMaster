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
        
        // Extended wait for cache clear
        Thread.sleep(forTimeInterval: 5.0)
        
        var apps: [InstalledApp] = []
        let fm = FileManager.default
        let appPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "~/Applications".expandingTildeInPath,
            "/Applications/Setapp"
        ]
        
        for path in appPaths {
            if let items = try? fm.contentsOfDirectory(atPath: path) {
                for item in items where item.hasSuffix(".app") {
                    let appPath = "\(path)/\(item)"
                    if let app = getAppInfo(at: appPath) {
                        apps.append(app)
                        print("Found: \(app.bundleId) v\(app.version) at \(appPath)")
                    }
                }
            }
        }
        
        // Scan subdirectories
        scanSubdirectories(at: "/Applications", apps: &apps)
        
        // Deduplicate by bundle ID
        let uniqueApps = Dictionary(grouping: apps, by: { $0.bundleId })
            .compactMap { $0.value.first }
        
        print("Found \(apps.count) total apps, \(uniqueApps.count) unique apps after deduplication")
        return uniqueApps
    }
    
    static func clearLaunchServicesCache() {
        print("🔄 Force clearing all caches...")
        
        // Clear bundle caches
        Bundle.main.executablePath // Force bundle system refresh
        
        let commands = [
                    ["/usr/bin/killall", "cfprefsd"],  // Preferences daemon
                    ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
                    ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
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
            Thread.sleep(forTimeInterval: 1.0) // Wait between commands
        }
        
        print("✅ All caches cleared")
    }
    
    private static func scanSubdirectories(at path: String, apps: inout [InstalledApp]) {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: path) {
            for item in items {
                let fullPath = "\(path)/\(item)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    if item.hasSuffix(".app") {
                        if let app = getAppInfo(at: fullPath) {
                            apps.append(app)
                        }
                    } else if !item.hasPrefix(".") {
                        if let subItems = try? fm.contentsOfDirectory(atPath: fullPath) {
                            for subItem in subItems where subItem.hasSuffix(".app") {
                                let appPath = "\(fullPath)/\(subItem)"
                                if let app = getAppInfo(at: appPath) {
                                    apps.append(app)
                                }
                            }
                        }
                    }
                }
            }
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
        
        // Special case: For Android Studio, always use CFBundleShortVersionString if available
        let version: String
        if bundleId == "com.google.android.studio", let short = shortVersion {
            version = short
        } else if let short = shortVersion, let bundle = bundleVersion {
            let shortCount = short.split(separator: ".").count
            let bundleCount = bundle.split(separator: ".").count
            version = (bundleCount > shortCount) ? bundle : short
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
