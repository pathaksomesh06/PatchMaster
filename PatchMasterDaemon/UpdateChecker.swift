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
            "com.docker.docker"                                        // Docker Desktop
        ])
    
    static func checkForUpdates(installedApps: [InstalledApp]) async throws -> [AppUpdate] {
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
        
        // Check Native Updates FIRST (like Parallels Desktop prlctl)
        // This ensures apps with native update mechanisms are handled natively
        print("\n=== Native Update Check ===")
        let nativeUpdates = try await NativeUpdateChecker.findUpdatesForInstalledApps(filteredApps)
        print("📋 Native updates found: \(nativeUpdates.count)")
        allUpdates.append(contentsOf: nativeUpdates)
        
        // Track which apps have native updates to avoid duplicates
        let appsWithNativeUpdates = Set(nativeUpdates.map { $0.installedBundleId })
        let appsWithoutNativeUpdates = filteredApps.filter { !appsWithNativeUpdates.contains($0.bundleId) }
        print("📋 Apps with native updates: \(appsWithNativeUpdates.count)")
        print("📋 Apps to check via other sources: \(appsWithoutNativeUpdates.count)")
        
        // Check Homebrew (only for apps without native updates)
        print("\n=== Homebrew Update Check ===")
        let homebrewUpdates = try await HomebrewChecker.findUpdatesForInstalledApps(appsWithoutNativeUpdates)
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
        
        return filteredUpdates
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
