//
//  UpdateChecker.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

class UpdateChecker {
    // Microsoft Office apps that are handled by Microsoft AutoUpdate (MAU)
    private static let microsoftOfficeApps = Set([
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Powerpoint",
        "com.microsoft.PowerPoint",
        "com.microsoft.OneNote",
        "com.microsoft.onenote.mac",
        "com.microsoft.Outlook",
        "com.microsoft.Office365ServiceV2",
        "com.microsoft.office",
        "com.microsoft.Office",
        "com.microsoft.teams2",
        "com.microsoft.teams"
    ])
    
    // Legacy/problematic apps that should be excluded from update checks
        private static let excludedApps = Set([
            // Docker Toolbox (legacy, deprecated)
            "com.apple.ScriptEditor.id.dockerquickstartterminalapp", // Docker Quickstart Terminal
            "com.electron.kitematic",                                  // Kitematic
            
            // Jabra Direct (problematic updates, use native updater)
            "com.jabra.directonline",                                 // Jabra Direct
            "com.jabra.JabraFirmwareUpdate",                         // Jabra Firmware Update
            
            // VirtualBox (often bundled with Docker Toolbox, complex installation)
            "org.virtualbox.app.VirtualBox",
            
            // Docker Desktop (complex updates, use Docker's built-in updater)
            "com.docker.docker",                                       // Docker Desktop
            
            // Cleartext (discontinued, Homebrew cask has wrong version data)
            "com.mortenjust.Simpler"                                   // Cleartext
        ])
    
    static func checkForUpdates(installedApps: [InstalledApp], requestId: String? = nil) async throws -> [AppUpdate] {
        // Report initial progress
        writeProgress(requestId: requestId, status: "Scanning installed apps...")
        
        var allUpdates: [AppUpdate] = []
        
        // Filter out Microsoft Office apps, Apple native apps, and excluded legacy apps
        let filteredApps = installedApps.filter { app in
            if microsoftOfficeApps.contains(app.bundleId) {
                print("⏭️ Skipping \(app.bundleId): Handled by Microsoft AutoUpdate (MAU)")
                return false
            }
            if app.bundleId.hasPrefix("com.apple.") {
                print("⏭️ Skipping \(app.bundleId): Apple native app")
                return false
            }
            if excludedApps.contains(app.bundleId) {
                let appName = (app.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                print("⏭️ Skipping \(app.bundleId): \(appName) - Legacy/problematic app excluded from updates")
                return false
            }
            return true
        }
        
        // Debug: Print all installed apps and their bundle IDs
        print("\n=== INSTALLED APPS DEBUG ===")
        for app in installedApps {
            let filtered = !filteredApps.contains { $0.bundleId == app.bundleId }
            let appName = (app.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            print("📱 \(appName) [\(app.bundleId)] - Version: \(app.version) - Filtered: \(filtered)")
        }
        print("===========================\n")
        
        print("📋 Filtered out \(installedApps.count - filteredApps.count) excluded apps (Microsoft Office, Apple native, legacy/problematic)")
        print("📋 Checking \(filteredApps.count) remaining apps for updates")
        
        // Report progress
        writeProgress(requestId: requestId, status: "Checking native updaters...")
        
        // Check Native Updates FIRST
        print("\n=== Native Update Check ===")
        let nativeUpdates = try await NativeUpdateChecker.findUpdatesForInstalledApps(filteredApps)
        print("📋 Native updates found: \(nativeUpdates.count)")
        allUpdates.append(contentsOf: nativeUpdates)
        
        // Track which apps have native updates to avoid duplicates
        let appsWithNativeUpdates = Set(nativeUpdates.map { $0.installedBundleId })
        let appsWithoutNativeUpdates = filteredApps.filter { !appsWithNativeUpdates.contains($0.bundleId) }
        
        writeProgress(requestId: requestId, status: "Checking Sparkle feeds...")
        
        // Check Sparkle feeds
        print("\n=== Sparkle Update Check ===")
        let sparkleUpdates = await SparkleUpdateChecker.findUpdatesForInstalledApps(appsWithoutNativeUpdates)
        print("📋 Sparkle updates found: \(sparkleUpdates.count)")
        allUpdates.append(contentsOf: sparkleUpdates)
        
        // Track apps checked via Sparkle
        let appsWithSparkleUpdates = Set(sparkleUpdates.map { $0.installedBundleId })
        let appsNotYetChecked = appsWithoutNativeUpdates.filter { 
            !appsWithSparkleUpdates.contains($0.bundleId)
        }
        
        writeProgress(requestId: requestId, status: "Checking Homebrew catalog...")
        
        // Check Homebrew (only for remaining apps)
        print("\n=== Homebrew Update Check ===")
        let homebrewUpdates = try await HomebrewChecker.findUpdatesForInstalledApps(appsNotYetChecked)
        print("📋 Homebrew updates found: \(homebrewUpdates.count)")
        allUpdates.append(contentsOf: homebrewUpdates)
        
        // Filter out false positives
        let filteredUpdates = allUpdates.filter { update in
            // Use the centralized VersionCompare for consistency
            let isNewer = VersionCompare.isNewer(update.newVersion, than: update.currentVersion)
            
            if !isNewer {
                print("⏭️ Skipping \(update.appName): \(update.currentVersion) >= \(update.newVersion)")
            }
            return isNewer
        }
        
        writeProgress(requestId: requestId, status: "Finalizing results...")
        
        return filteredUpdates
    }
    
    static func writeProgress(requestId: String?, status: String) {
        guard let requestId = requestId else { return }
        
        let progressDir = "/tmp/patchmaster-ipc/progress"
        let progressFile = "\(progressDir)/\(requestId).json"
        
        let progressData: [String: Any] = [
            "requestId": requestId,
            "status": status,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: progressData) {
            try? jsonData.write(to: URL(fileURLWithPath: progressFile))
        }
    }
    
    // Debug method to analyze version detection issues
    static func debugVersionDetection(for bundleId: String, appName: String) {
        print("\n=== DEBUG VERSION DETECTION ===")
        print("App: \(appName)")
        print("Bundle ID: \(bundleId)")
        
        // Check multiple possible locations
        let possiblePaths = [
            "/Applications/\(appName).app",
            "/Applications/\(appName)",
            "/Applications/Utilities/\(appName).app",
            "/System/Applications/\(appName).app"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                print("✅ Found app at: \(path)")
                
                let plistPath = "\(path)/Contents/Info.plist"
                if let plist = NSDictionary(contentsOfFile: plistPath) {
                    print("   Bundle ID: \(plist["CFBundleIdentifier"] as? String ?? "unknown")")
                    print("   Short Version: \(plist["CFBundleShortVersionString"] as? String ?? "unknown")")
                    print("   Bundle Version: \(plist["CFBundleVersion"] as? String ?? "unknown")")
                    print("   Get Info: \(plist["CFBundleGetInfoString"] as? String ?? "unknown")")
                    
                    // Show all possible version keys
                    print("   All version-related keys:")
                    for (key, value) in plist {
                        if let keyStr = key as? String, keyStr.lowercased().contains("version") {
                            print("     \(keyStr): \(value)")
                        }
                    }
                }
            }
        }
        
        // Also check via NSWorkspace
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            print("✅ NSWorkspace found: \(appURL.path)")
            
            if let bundle = Bundle(url: appURL) {
                print("   Bundle short version: \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")")
                print("   Bundle version: \(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")")
            }
        }
        
        print("===============================\n")
    }
    

}
