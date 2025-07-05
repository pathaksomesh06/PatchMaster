//
//  DebugCatalog.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//


import Foundation

class DebugCatalog {
    static func printMissingApps() async {
        let missingApps = [
            "zoom",
            "microsoft_office", 
            "company_portal",
            "microsoft_teams",
            "displaylink_usb_graphics_software"
        ]
        
        let catalogURL = "https://raw.githubusercontent.com/ugurkocde/IntuneBrew/main/supported_apps.json"
        
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: catalogURL)!)
            let catalog = try JSONDecoder().decode([String: String].self, from: data)
            
            for appName in missingApps {
                if let url = catalog[appName] {
                    let (appData, _) = try await URLSession.shared.data(from: URL(string: url)!)
                    if let json = try? JSONDecoder().decode(IntuneBrweApp.self, from: appData) {
                        print("\n\(appName):")
                        print("  Catalog Bundle ID: \(json.bundleId)")
                    }
                }
            }
        } catch {
            print("Error: \(error)")
        }
    }
}