//
//  AppModels.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

// Generic app structure for updates
struct AppInfo: Codable {
    let name: String
    let description: String
    let version: String
    let url: String?
    let bundleId: String
    let homepage: String?
    let fileName: String?
}

struct InstalledApp: Codable {
    let bundleId: String
    let version: String
    let path: String
    let icon: NSImage?
    
    enum CodingKeys: String, CodingKey {
        case bundleId, version, path, iconData
    }
    
    init(bundleId: String, version: String, path: String, icon: NSImage?) {
        self.bundleId = bundleId
        self.version = version
        self.path = path
        self.icon = icon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        version = try container.decode(String.self, forKey: .version)
        path = try container.decode(String.self, forKey: .path)
        
        if let iconData = try container.decodeIfPresent(Data.self, forKey: .iconData) {
            icon = NSImage(data: iconData)
        } else {
            icon = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(version, forKey: .version)
        try container.encode(path, forKey: .path)
        
    }
}

struct HomebrewCask: Codable {
    let token: String
    let name: [String]
    let version: String
    let homepage: String?
    let url: String?
    let desc: String?
    let artifacts: [HomebrewArtifact]?
    
    var displayName: String {
        return name.first ?? token
    }
    
    var description: String {
        return desc ?? ""
    }
}

struct HomebrewArtifact: Codable {
    let app: [HomebrewApp]?
    
    enum CodingKeys: String, CodingKey {
        case app
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if container.contains(.app) {
            // Handle both string arrays and dictionaries in the app field
            do {
                // Try to decode as array of strings first
                let appStrings = try container.decode([String].self, forKey: .app)
                self.app = appStrings.map { HomebrewApp.fromString($0) }
            } catch {
                // If that fails, try to decode as array of objects
                do {
                    self.app = try container.decode([HomebrewApp].self, forKey: .app)
                } catch {
                    // If both fail, set to nil
                    self.app = nil
                }
            }
        } else {
            self.app = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(app, forKey: .app)
    }
}

struct HomebrewApp: Codable {
    let name: String?
    let target: String?
    
    static func fromString(_ string: String) -> HomebrewApp {
        return HomebrewApp(name: string, target: nil)
    }
}

enum UpdateSource: String, Codable {
    case homebrew = "homebrew"
    case native = "native"
    case sparkle = "sparkle"
    
    var displayName: String {
        switch self {
        case .sparkle:
            return "Sparkle"
        case .homebrew:
            return "Homebrew"
        case .native:
            return "Native"
        }
    }
    
    var color: String {
        switch self {
        case .sparkle:
            return "purple"
        case .homebrew:
            return "orange"
        case .native:
            return "green"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .sparkle:
            return "sparkles"
        case .homebrew:
            return "terminal"
        case .native:
            return "gear.badge"
        }
    }
}

struct AppUpdate: Codable {
    let appInfo: AppInfo?
    let homebrewCask: HomebrewCask?
    let currentVersion: String
    let newVersion: String
    let installedAppIcon: NSImage?
    let source: UpdateSource
    let installedBundleId: String
    
    enum CodingKeys: String, CodingKey {
        case appInfo, homebrewCask, currentVersion, newVersion, iconData, source, installedBundleId
    }
    
    init(appInfo: AppInfo?, homebrewCask: HomebrewCask?, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, source: UpdateSource, installedBundleId: String) {
        self.appInfo = appInfo
        self.homebrewCask = homebrewCask
        self.currentVersion = currentVersion
        self.newVersion = newVersion
        self.installedAppIcon = installedAppIcon
        self.source = source
        self.installedBundleId = installedBundleId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appInfo = try container.decodeIfPresent(AppInfo.self, forKey: .appInfo)
        homebrewCask = try container.decodeIfPresent(HomebrewCask.self, forKey: .homebrewCask)
        currentVersion = try container.decode(String.self, forKey: .currentVersion)
        newVersion = try container.decode(String.self, forKey: .newVersion)
        source = try container.decode(UpdateSource.self, forKey: .source)
        installedBundleId = try container.decode(String.self, forKey: .installedBundleId)
        
        if let iconData = try container.decodeIfPresent(Data.self, forKey: .iconData) {
            installedAppIcon = NSImage(data: iconData)
        } else {
            installedAppIcon = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(appInfo, forKey: .appInfo)
        try container.encodeIfPresent(homebrewCask, forKey: .homebrewCask)
        try container.encode(currentVersion, forKey: .currentVersion)
        try container.encode(newVersion, forKey: .newVersion)
        try container.encode(source, forKey: .source)
        try container.encode(installedBundleId, forKey: .installedBundleId)
    }
    
    // Computed properties to unify access
    var appName: String {
        return appInfo?.name ?? homebrewCask?.displayName ?? "Unknown"
    }
    
    var appDescription: String {
        return appInfo?.description ?? homebrewCask?.description ?? ""
    }
    
    var homepage: String {
        return appInfo?.homepage ?? homebrewCask?.homepage ?? ""
    }
    
    var downloadURL: String? {
        return appInfo?.url ?? homebrewCask?.url
    }
    
    var fileName: String? {
        return appInfo?.fileName
    }
    
    // Computed ID for ForEach
    var id: String {
        return "\(source.displayName)-\(appName)-\(newVersion)"
    }
    
    // Convenience initializers

    
    static func fromHomebrew(cask: HomebrewCask, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, installedBundleId: String) -> AppUpdate {
        return AppUpdate(
            appInfo: nil,
            homebrewCask: cask,
            currentVersion: VersionCompare.cleanVersionForDisplay(currentVersion),
            newVersion: VersionCompare.cleanVersionForDisplay(newVersion),
            installedAppIcon: installedAppIcon,
            source: .homebrew,
            installedBundleId: installedBundleId
        )
    }
    
    static func fromNative(appName: String, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, installedBundleId: String, updateCommand: String) -> AppUpdate {
        let cleanNew = VersionCompare.cleanVersionForDisplay(newVersion)
        let nativeApp = AppInfo(
            name: appName,
            description: "Native update via built-in mechanism",
            version: cleanNew,
            url: updateCommand,
            bundleId: installedBundleId,
            homepage: nil,
            fileName: nil
        )
        
        return AppUpdate(
            appInfo: nativeApp,
            homebrewCask: nil,
            currentVersion: VersionCompare.cleanVersionForDisplay(currentVersion),
            newVersion: cleanNew,
            installedAppIcon: installedAppIcon,
            source: .native,
            installedBundleId: installedBundleId
        )
    }
}


struct SimpleAppUpdate: Codable {
    let appName: String
    let currentVersion: String
    let newVersion: String
    let downloadURL: String?
    let source: String
    let installedBundleId: String
    
    init(from appUpdate: AppUpdate) {
        self.appName = appUpdate.appName
        self.currentVersion = appUpdate.currentVersion
        self.newVersion = appUpdate.newVersion
        self.source = appUpdate.source.rawValue
        self.installedBundleId = appUpdate.installedBundleId
        self.downloadURL = appUpdate.downloadURL
    }
}
