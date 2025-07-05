//
//  IntuneBrewChecker.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

class IntuneBrewChecker {
    static let catalogURL = "https://raw.githubusercontent.com/ugurkocde/IntuneBrew/main/supported_apps.json"
    private static var cachedCatalog: [String: String] = [:]
    private static var lastCacheTime: Date = Date.distantPast
    private static let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    // Microsoft Office apps that should be excluded from IntuneBrew checking
    private static let excludedApps = Set([
        "microsoft_office",
        "microsoft_teams", 
        "company_portal",
        "microsoft_word",
        "microsoft_excel",
        "microsoft_powerpoint",
        "microsoft_outlook",
        "microsoft_onenote"
    ])
    
    // Microsoft Office bundle IDs that should be excluded
    private static let excludedBundleIds = Set([
        "com.microsoft.Word",
        "com.microsoft.Excel", 
        "com.microsoft.Powerpoint",
        "com.microsoft.PowerPoint",
        "com.microsoft.Outlook",
        "com.microsoft.OneNote",
        "com.microsoft.onenote.mac",
        "com.microsoft.Office365ServiceV2",
        "com.microsoft.office",
        "com.microsoft.Office",
        "com.microsoft.Office365",
        "com.microsoft.package.Microsoft_Office_16",
        "com.microsoft.package.DFU",
        "com.microsoft.autoupdate",
        "com.microsoft.autoupdate2",
        "com.microsoft.update.agent",
        "com.microsoft.teams",
        "com.microsoft.teams2"
    ])
    
    static func fetchCatalog() async throws -> [String: String] {
        // Use cache if recent
        if Date().timeIntervalSince(lastCacheTime) < cacheTimeout && !cachedCatalog.isEmpty {
            return cachedCatalog
        }
        
        print("🔵 Fetching IntuneBrew catalog...")
        let (data, _) = try await URLSession.shared.data(from: URL(string: catalogURL)!)
        let catalog = try JSONDecoder().decode([String: String].self, from: data)
        
        cachedCatalog = catalog
        lastCacheTime = Date()
        print("🔵 Fetched \(catalog.count) IntuneBrew apps")
        
        return catalog
    }
    
    static func findUpdatesForInstalledApps(_ installedApps: [InstalledApp]) async throws -> [AppUpdate] {
        let catalog = try await fetchCatalog()
        var updates: [AppUpdate] = []
        
        print("\n🔵 === IntuneBrew Update Check ===")
        
        // Check each installed app against IntuneBrew catalog
        for app in installedApps {
            // Skip Microsoft Office apps (handled by MAU)
            if app.bundleId.hasPrefix("com.microsoft.") {
                print("⏭️ Skipping \(app.bundleId): Microsoft app handled by MAU")
                continue
            }
            
            // Skip specific Microsoft Office bundle IDs
            if excludedBundleIds.contains(app.bundleId) {
                print("⏭️ Skipping \(app.bundleId): Microsoft Office app excluded")
                continue
            }
            
            // Skip any app with Microsoft Office bundle IDs
            if app.bundleId.contains("microsoft") && (app.bundleId.contains("word") || app.bundleId.contains("excel") || app.bundleId.contains("powerpoint") || app.bundleId.contains("outlook") || app.bundleId.contains("onenote") || app.bundleId.contains("office")) {
                print("⏭️ Skipping \(app.bundleId): Microsoft Office app detected")
                continue
            }
            
                    // Try to find matching app in IntuneBrew catalog
        if let appURL = findMatchingAppInCatalog(app: app, catalog: catalog) {
            // Additional check: skip if the catalog entry is for microsoft_office
            let appName = URL(fileURLWithPath: app.path).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
                .lowercased()
            
            if appName.contains("microsoft") || app.bundleId.contains("microsoft") {
                print("⏭️ Skipping \(app.bundleId): Microsoft app detected in catalog")
                continue
            }
                do {
                    let (appData, _) = try await URLSession.shared.data(from: URL(string: appURL)!)
                    if let intuneApp = try? JSONDecoder().decode(IntuneBrweApp.self, from: appData) {
                        print("\n🔵 Found in IntuneBrew: \(intuneApp.name)")
                        print("  Bundle ID: \(app.bundleId)")
                        print("  Installed: \(app.version)")
                        print("  IntuneBrew: \(intuneApp.version)")
                        
                        if VersionCompare.isNewer(intuneApp.version, than: app.version) {
                            print("  ✅ Update available via IntuneBrew!")
                            
                            let update = AppUpdate.fromIntuneBrew(
                                app: intuneApp,
                                currentVersion: app.version,
                                newVersion: intuneApp.version,
                                installedAppIcon: app.icon,
                                installedBundleId: app.bundleId
                            )
                            updates.append(update)
                        } else {
                            print("  ✅ Up to date")
                        }
                    }
                } catch {
                    print("  ❌ Failed to fetch app details: \(error.localizedDescription)")
                }
            }
        }
        
        print("\n🔵 IntuneBrew found \(updates.count) updates")
        return updates
    }
    
    private static func findMatchingAppInCatalog(app: InstalledApp, catalog: [String: String]) -> String? {
        let appName = URL(fileURLWithPath: app.path).lastPathComponent
            .replacingOccurrences(of: ".app", with: "")
            .lowercased()
        
        // Skip excluded apps
        if excludedApps.contains(appName) {
            print("⏭️ Skipping \(appName): Excluded from IntuneBrew")
            return nil
        }
        
        // Skip Microsoft Office apps by name variations
        if appName.contains("microsoft") && (appName.contains("office") || appName.contains("word") || appName.contains("excel") || appName.contains("powerpoint") || appName.contains("outlook") || appName.contains("onenote")) {
            print("⏭️ Skipping \(appName): Microsoft Office app excluded")
            return nil
        }
        
        // Try direct name match
        if let url = catalog[appName] {
            return url
        }
        
        // Try with underscores (common in IntuneBrew)
        let underscoredName = appName.replacingOccurrences(of: "-", with: "_")
        if let url = catalog[underscoredName] {
            return url
        }
        
        // Try with hyphens
        let hyphenatedName = appName.replacingOccurrences(of: "_", with: "-")
        if let url = catalog[hyphenatedName] {
            return url
        }
        
        // Try fuzzy matching
        for (catalogName, url) in catalog {
            if catalogName.contains(appName) || appName.contains(catalogName) {
                print("🔍 Fuzzy match: \(appName) -> \(catalogName)")
                return url
            }
        }
        
        return nil
    }
} 