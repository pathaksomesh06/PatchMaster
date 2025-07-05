//
//  HomebrewChecker.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

class HomebrewChecker {
    static let caskAPIURL = "https://formulae.brew.sh/api/cask.json"
    private static var cachedCasks: [HomebrewCask] = []
    private static var lastCacheTime: Date = Date.distantPast
    private static let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    // Manual bundle ID to name mapping for edge cases
    private static let manualBundleIdNameMapping: [String: String] = [
        "com.latenightsw.Script-Notary2": "SD Notary 2"
    ]
    
    static func fetchAllCasks() async throws -> [HomebrewCask] {
        // Use cache if recent
        if Date().timeIntervalSince(lastCacheTime) < cacheTimeout && !cachedCasks.isEmpty {
            print("🍺 Using cached Homebrew catalog (\(cachedCasks.count) casks)")
            return cachedCasks
        }
        
        print("🍺 Fetching fresh Homebrew Cask catalog...")
        let (data, _) = try await URLSession.shared.data(from: URL(string: caskAPIURL)!)
        let casks = try JSONDecoder().decode([HomebrewCask].self, from: data)
        
        cachedCasks = casks
        lastCacheTime = Date()
        print("🍺 Successfully fetched \(casks.count) Homebrew casks")
        
        return casks
    }
    
    static func findUpdatesForInstalledApps(_ installedApps: [InstalledApp]) async throws -> [AppUpdate] {
        print("🍺 Starting Homebrew update check for \(installedApps.count) apps...")
        
        let casks = try await fetchAllCasks()
        var updates: [AppUpdate] = []
        
        // Create optimized mappings for faster lookup
        print("🍺 Building app mappings...")
        let bundleIdMappings = createBundleIdMappings(from: casks)
        let appNameMappings = createAppNameMappings(from: casks)
        
        print("🍺 Created \(bundleIdMappings.count) bundle ID mappings")
        print("🍺 Created \(appNameMappings.count) app name mappings")
        
        // Check each installed app
        var foundCount = 0
        var updateCount = 0
        
        for app in installedApps {
            let appName = URL(fileURLWithPath: app.path).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            
            // Manual mapping for edge cases: completely override Homebrew matching
            if let manualName = manualBundleIdNameMapping[app.bundleId] {
                print("📝 Manual mapping for \(app.bundleId): \(manualName)")
                // Use the installed version as current, and Homebrew version if available for update
                let cask = bundleIdMappings[app.bundleId]
                let newVersion = cask?.version ?? app.version
                let updateAvailable = VersionCompare.isNewer(newVersion, than: app.version)
                print("   📦 Bundle ID: \(app.bundleId)")
                print("   📊 Installed: \(app.version) | Homebrew: \(newVersion)")
                if updateAvailable {
                    print("   ✅ UPDATE AVAILABLE!")
                    let update = AppUpdate(
                        app: nil,
                        homebrewCask: cask,
                        currentVersion: app.version,
                        newVersion: newVersion,
                        installedAppIcon: app.icon,
                        source: .homebrew,
                        installedBundleId: app.bundleId
                    )
                    updates.append(update)
                } else {
                    print("   ✅ Up to date")
                }
                foundCount += 1
                continue
            }
            
            var matchedCask: HomebrewCask? = nil
            var matchType = "none"
            var displayName: String? = nil
            
            // Strategy 1: Direct bundle ID match (most reliable)
            if let cask = bundleIdMappings[app.bundleId] {
                matchedCask = cask
                matchType = "bundle-id"
                displayName = cask.displayName
            }
            // Strategy 2: Exact app name match (case-insensitive)
            else if let cask = appNameMappings[appName.lowercased()] {
                matchedCask = cask
                matchType = "app-name-exact"
                displayName = cask.displayName
            }
            // Strategy 3: App name variations
            else if let cask = findCaskByAppName(appName: appName, mappings: appNameMappings) {
                matchedCask = cask
                matchType = "app-name-variation"
                displayName = cask.displayName
            }
            // Strategy 4: Fuzzy matching (last resort)
            else if let cask = findCaskByFuzzyMatch(appName: appName, casks: casks) {
                matchedCask = cask
                matchType = "fuzzy"
                displayName = cask.displayName
                print("⚠️ Fuzzy match used for \(appName) → \(cask.displayName)")
            }
            
            if let cask = matchedCask {
                foundCount += 1
                let shownName = displayName ?? cask.displayName
                print("🍺 Found: \(appName) → \(shownName) (via \(matchType))")
                print("   📦 Bundle ID: \(app.bundleId)")
                print("   📊 Installed: \(app.version) | Homebrew: \(cask.version)")
                
                if VersionCompare.isNewer(cask.version, than: app.version) {
                    updateCount += 1
                    print("   ✅ UPDATE AVAILABLE!")
                    
                    let update = AppUpdate.fromHomebrew(
                        cask: cask,
                        currentVersion: app.version,
                        newVersion: cask.version,
                        installedAppIcon: app.icon,
                        installedBundleId: app.bundleId
                    )
                    updates.append(update)
                } else {
                    print("   ✅ Up to date")
                }
            } else if let manualName = displayName {
                print("🍺 Manual mapping used: \(manualName) for \(app.bundleId)")
            } else {
                print("🍺 Not found: \(appName) [\(app.bundleId)]")
            }
        }
        
        print("\n🍺 === HOMEBREW RESULTS ===")
        print("📋 Apps found in Homebrew: \(foundCount)/\(installedApps.count)")
        print("📋 Updates available: \(updateCount)")
        print("===========================\n")
        
        return updates
    }
    
    // Optimized app name matching with multiple strategies
    private static func findCaskByAppName(appName: String, mappings: [String: HomebrewCask]) -> HomebrewCask? {
        let variations = generateAppNameVariations(appName)
        
        for variation in variations {
            if let cask = mappings[variation] {
                return cask
            }
        }
        
        return nil
    }
    
    // Generate multiple variations of app name for better matching
    private static func generateAppNameVariations(_ appName: String) -> [String] {
        let base = appName.lowercased()
        
        return [
            base,                                               // "visual studio code"
            base.replacingOccurrences(of: " ", with: "-"),     // "visual-studio-code"
            base.replacingOccurrences(of: " ", with: "_"),     // "visual_studio_code"
            base.replacingOccurrences(of: " ", with: ""),      // "visualstudiocode"
            base.replacingOccurrences(of: "-", with: "_"),     // handle existing hyphens
            base.replacingOccurrences(of: "_", with: "-"),     // handle existing underscores
            base.components(separatedBy: " ").first ?? base    // "visual" (first word only)
        ]
    }
    
    // Enhanced app name mappings with better coverage
    private static func createAppNameMappings(from casks: [HomebrewCask]) -> [String: HomebrewCask] {
        var mappings: [String: HomebrewCask] = [:]
        
        for cask in casks {
            // Map by all display names
            for name in cask.name {
                let variations = generateAppNameVariations(name)
                for variation in variations {
                    mappings[variation] = cask
                }
            }
            
            // Map by cask token and its variations
            let tokenVariations = generateAppNameVariations(cask.token)
            for variation in tokenVariations {
                mappings[variation] = cask
            }
            
            // Map by app artifact names
            if let artifacts = cask.artifacts {
                for artifact in artifacts {
                    if let apps = artifact.app {
                        for app in apps {
                            if let appName = app.name {
                                let cleanName = appName.replacingOccurrences(of: ".app", with: "")
                                let variations = generateAppNameVariations(cleanName)
                                for variation in variations {
                                    mappings[variation] = cask
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return mappings
    }
    
    // Enhanced fuzzy matching with stricter scoring
    private static func findCaskByFuzzyMatch(appName: String, casks: [HomebrewCask]) -> HomebrewCask? {
        let cleanAppName = appName.lowercased()
        var bestMatch: HomebrewCask?
        var bestScore = 0.0
        
        // Increased threshold from 0.7 to 0.85 for stricter matching
        let minimumScore = 0.85
        
        for cask in casks {
            let score = calculateMatchScore(appName: cleanAppName, cask: cask)
            if score > bestScore && score >= minimumScore {
                bestScore = score
                bestMatch = cask
            }
        }
        
        // Additional validation: reject if app name is too short for fuzzy matching
        if cleanAppName.count <= 3 {
            return nil
        }
        
        return bestMatch
    }
    
    // Calculate match score with stricter criteria
    private static func calculateMatchScore(appName: String, cask: HomebrewCask) -> Double {
        let tokenScore = calculateStringScore(appName, cask.token)
        
        var nameScore = 0.0
        for name in cask.name {
            nameScore = max(nameScore, calculateStringScore(appName, name.lowercased()))
        }
        
        let finalScore = max(tokenScore, nameScore)
        
        // Reject very short matches that could be coincidental
        if appName.count <= 4 && finalScore < 0.95 {
            return 0.0
        }
        
        return finalScore
    }
    
    // Enhanced string scoring with length penalties
    private static func calculateStringScore(_ str1: String, _ str2: String) -> Double {
        // Exact match
        if str1 == str2 { return 1.0 }
        
        // Length difference penalty
        let lengthDiff = abs(str1.count - str2.count)
        let maxLength = max(str1.count, str2.count)
        let lengthPenalty = Double(lengthDiff) / Double(maxLength)
        
        // If length difference is too large, reject
        if lengthPenalty > 0.5 { return 0.0 }
        
        // Contains match with length penalty
        if str1.contains(str2) || str2.contains(str1) {
            return 0.8 - (lengthPenalty * 0.3)
        }
        
        // Levenshtein distance with stricter scoring
        let distance = levenshteinDistance(str1, str2)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        
        // Apply additional length penalty to final score
        return max(0.0, similarity - lengthPenalty)
    }
    
    // Simple Levenshtein distance calculation
    private static func levenshteinDistance(_ str1: String, _ str2: String) -> Int {
        let a = Array(str1)
        let b = Array(str2)
        
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return matrix[a.count][b.count]
    }
    
    // Enhanced bundle ID mappings with comprehensive coverage
    private static func createBundleIdMappings(from casks: [HomebrewCask]) -> [String: HomebrewCask] {
        var mappings: [String: HomebrewCask] = [:]
        
        // Load comprehensive known mappings
        let knownMappings = loadKnownBundleIdMappings()
        
        for cask in casks {
            if let bundleIds = knownMappings[cask.token] {
                for bundleId in bundleIds {
                    mappings[bundleId] = cask
                }
            }
        }
        
        print("🍺 Loaded \(mappings.count) known bundle ID mappings")
        return mappings
    }
    
    // Comprehensive bundle ID mappings - focusing on most common apps
    private static func loadKnownBundleIdMappings() -> [String: [String]] {
        return [
            // Development Tools
            "visual-studio-code": ["com.microsoft.VSCode"],
            "cursor": ["com.todesktop.230313mzl4w4u92"],
            "sublime-text": ["com.sublimetext.4"],
            "intellij-idea": ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"],
            "pycharm": ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"],
            "webstorm": ["com.jetbrains.webstorm"],
            "android-studio": ["com.google.android.studio"],
            "github": ["com.github.GitHubClient"],
            "sourcetree": ["com.torusknot.SourceTreeNotMAS"],
            "docker-desktop": ["com.docker.docker"], // Docker Desktop (modern)
            "postman": ["com.postmanlabs.mac"],
            
            // Browsers
            "google-chrome": ["com.google.Chrome"],
            "firefox": ["org.mozilla.firefox"],
            "brave-browser": ["com.brave.Browser"],
            "microsoft-edge": ["com.microsoft.edgemac"],
            "arc": ["company.thebrowser.Browser"],
            "opera": ["com.operasoftware.Opera"],
            "vivaldi": ["com.vivaldi.Vivaldi"],
            
            // Communication
            "slack": ["com.tinyspeck.slackmacgap"],
            "discord": ["com.hnc.Discord"],
            "zoom": ["us.zoom.xos"],
            "telegram": ["ru.keepcoder.Telegram"],
            "whatsapp": ["net.whatsapp.WhatsApp"],
            "signal": ["org.whispersystems.signal-desktop"],
            
            // Productivity
            "notion": ["notion.id"],
            "obsidian": ["md.obsidian"],
            "1password": ["com.1password.1password", "com.agilebits.onepassword7"],
            "alfred": ["com.runningwithcrayons.Alfred"],
            "raycast": ["com.raycast.macos"],
            "rectangle": ["com.knollsoft.Rectangle"],
            "magnet": ["com.crowdcafe.Magnet"],
            
            // Media
            "spotify": ["com.spotify.client"],
            "vlc": ["org.videolan.vlc"],
            "iina": ["com.colliderli.iina"],
            "handbrake": ["fr.handbrake.HandBrake"],
            
            // Design
            "figma": ["com.figma.Desktop"],
            "sketch": ["com.bohemiancoding.sketch3"],
            "pixelmator-pro": ["com.pixelmatorteam.pixelmator.x"],
            
            // Utilities
            "cleanmymac": ["com.macpaw.CleanMyMac4", "com.macpaw.CleanMyMac-X"],
            "bartender": ["com.surteesstudios.Bartender-4"],
            "the-unarchiver": ["cx.c3.theunarchiver"],
            "istat-menus": ["com.bjango.istatmenus"],
            "little-snitch": ["at.obdev.LittleSnitch"],
            
            // Terminal
            "iterm2": ["com.googlecode.iterm2"],
            "warp": ["dev.warp.Warp"],
            
            // Cloud Storage
            "dropbox": ["com.getdropbox.dropbox"],
            "google-drive": ["com.google.GoogleDrive"],
            
            // Virtualization
            "parallels": ["com.parallels.desktop.console"],
            "vmware-fusion": ["com.vmware.fusion"],
            "virtualbox": ["org.virtualbox.app.VirtualBox"],
            
            // AI Tools
            "chatgpt": ["com.openai.chat"],
            "claude": ["com.anthropic.claudefordesktop"]
        ]
    }
}
