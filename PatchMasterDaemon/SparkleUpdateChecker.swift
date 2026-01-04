//
//  SparkleUpdateChecker.swift
//  PatchMaster
//
//  Check for updates via Sparkle appcast feeds
//

import Foundation

class SparkleUpdateChecker {
    
    static func findSparkleURL(for app: InstalledApp) -> String? {
        let plistPath = "\(app.path)/Contents/Info.plist"
        
        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let sparkleURL = plist["SUFeedURL"] as? String else {
            return nil
        }
        
        return sparkleURL
    }
    
    static func checkSparkleUpdate(feedURL: String, currentVersion: String) async throws -> String? {
        let (data, _) = try await URLSession.shared.data(from: URL(string: feedURL)!)
        
        let parser = XMLParser(data: data)
        let delegate = SparkleXMLDelegate()
        parser.delegate = delegate
        parser.parse()
        
        if let latestVersion = delegate.latestVersion,
           VersionCompare.isNewer(latestVersion, than: currentVersion) {
            return latestVersion
        }
        
        return nil
    }
    
    static func findUpdatesForInstalledApps(_ installedApps: [InstalledApp]) async -> [AppUpdate] {
        var updates: [AppUpdate] = []
        
        print("\n=== Sparkle Update Check ===")
        
        for app in installedApps {
            guard let sparkleURL = findSparkleURL(for: app) else { continue }
            
            print("🔍 Found Sparkle feed for \(app.bundleId)")
            
            do {
                if let newVersion = try await checkSparkleUpdate(feedURL: sparkleURL, currentVersion: app.version) {
                    print("  ✅ Update available: \(app.version) → \(newVersion)")
                    
                    let appName = URL(fileURLWithPath: app.path).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                    let appInfo = AppInfo(
                        name: appName,
                        description: "Update via Sparkle framework",
                        version: newVersion,
                        url: sparkleURL,
                        bundleId: app.bundleId,
                        homepage: nil,
                        fileName: nil
                    )
                    let update = AppUpdate(
                        appInfo: appInfo,
                        homebrewCask: nil,
                        currentVersion: app.version,
                        newVersion: newVersion,
                        installedAppIcon: app.icon,
                        source: .sparkle,
                        installedBundleId: app.bundleId
                    )
                    updates.append(update)
                }
            } catch {
                print("  ❌ Failed to check Sparkle feed: \(error)")
            }
        }
        
        print("Sparkle checker found \(updates.count) updates")
        return updates
    }
}

class SparkleXMLDelegate: NSObject, XMLParserDelegate {
    var latestVersion: String?
    private var currentElement = ""
    private var foundFirstItem = false
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "item" && !foundFirstItem {
            foundFirstItem = true
        }
        
        if elementName == "enclosure" && foundFirstItem {
            // Prefer shortVersionString (human-readable like "2.0.1") over version (build number like "102")
            if let shortVersion = attributeDict["sparkle:shortVersionString"], !shortVersion.isEmpty {
                latestVersion = shortVersion
            } else if let version = attributeDict["sparkle:version"] {
                latestVersion = version
            }
        }
    }
}
