//
//  AppModels.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

struct IntuneBrweApp: Codable {
    let name: String
    let description: String
    let version: String
    let url: String
    let bundleId: String
    let homepage: String
    let fileName: String
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
        
        // Don't serialize icon data - too large for IPC
        // Icons will be loaded separately in the main app
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
    case intuneBrew = "intuneBrew"
    case homebrew = "homebrew"
    case native = "native"
    
    var displayName: String {
        switch self {
        case .intuneBrew:
            return "IntuneBrew"
        case .homebrew:
            return "Homebrew"
        case .native:
            return "Native"
        }
    }
    
    var color: String {
        switch self {
        case .intuneBrew:
            return "blue"
        case .homebrew:
            return "orange"
        case .native:
            return "green"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .intuneBrew:
            return "cube.box"
        case .homebrew:
            return "terminal"
        case .native:
            return "gear.badge"
        }
    }
}

struct AppUpdate: Codable {
    let app: IntuneBrweApp?
    let homebrewCask: HomebrewCask?
    let currentVersion: String
    let newVersion: String
    let installedAppIcon: NSImage?
    let source: UpdateSource
    let installedBundleId: String
    
    enum CodingKeys: String, CodingKey {
        case app, homebrewCask, currentVersion, newVersion, iconData, source, installedBundleId
    }
    
    init(app: IntuneBrweApp?, homebrewCask: HomebrewCask?, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, source: UpdateSource, installedBundleId: String) {
        self.app = app
        self.homebrewCask = homebrewCask
        self.currentVersion = currentVersion
        self.newVersion = newVersion
        self.installedAppIcon = installedAppIcon
        self.source = source
        self.installedBundleId = installedBundleId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decodeIfPresent(IntuneBrweApp.self, forKey: .app)
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
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(homebrewCask, forKey: .homebrewCask)
        try container.encode(currentVersion, forKey: .currentVersion)
        try container.encode(newVersion, forKey: .newVersion)
        try container.encode(source, forKey: .source)
        try container.encode(installedBundleId, forKey: .installedBundleId)
        
        // Don't serialize icon data - too large for IPC
        // Icons will be loaded separately in the main app
    }
    
    // Computed properties to unify access
    var appName: String {
        return app?.name ?? homebrewCask?.displayName ?? "Unknown"
    }
    
    var appDescription: String {
        return app?.description ?? homebrewCask?.description ?? ""
    }
    
    var homepage: String {
        return app?.homepage ?? homebrewCask?.homepage ?? ""
    }
    
    var downloadURL: String? {
        return app?.url ?? homebrewCask?.url
    }
    
    var fileName: String? {
        return app?.fileName
    }
    
    // Computed ID for ForEach
    var id: String {
        return "\(source.displayName)-\(appName)-\(newVersion)"
    }
    
    // Convenience initializers
    static func fromIntuneBrew(app: IntuneBrweApp, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, installedBundleId: String) -> AppUpdate {
        return AppUpdate(
            app: app,
            homebrewCask: nil,
            currentVersion: currentVersion,
            newVersion: newVersion,
            installedAppIcon: installedAppIcon,
            source: .intuneBrew,
            installedBundleId: installedBundleId
        )
    }
    
    static func fromHomebrew(cask: HomebrewCask, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, installedBundleId: String) -> AppUpdate {
        return AppUpdate(
            app: nil,
            homebrewCask: cask,
            currentVersion: currentVersion,
            newVersion: newVersion,
            installedAppIcon: installedAppIcon,
            source: .homebrew,
            installedBundleId: installedBundleId
        )
    }
    
    static func fromNative(appName: String, currentVersion: String, newVersion: String, installedAppIcon: NSImage?, installedBundleId: String, updateCommand: String) -> AppUpdate {
        // Create a minimal IntuneBrweApp-like structure for native updates
        let nativeApp = IntuneBrweApp(
            name: appName,
            description: "Native update via built-in mechanism",
            version: newVersion,
            url: updateCommand, // Store the update command in the URL field
            bundleId: installedBundleId,
            homepage: "",
            fileName: ""
        )
        
        return AppUpdate(
            app: nativeApp,
            homebrewCask: nil,
            currentVersion: currentVersion,
            newVersion: newVersion,
            installedAppIcon: installedAppIcon,
            source: .native,
            installedBundleId: installedBundleId
        )
    }
}

// Simplified structure that matches the main app's MockAppUpdate
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
