//
//  VersionCompare.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//


import Foundation

class VersionCompare {
    static func isNewer(_ newVersion: String, than currentVersion: String) -> Bool {
        // Strip build numbers and compare base versions only
        let cleanNew = cleanVersion(newVersion)
        let cleanCurrent = cleanVersion(currentVersion)
        
        print("🔍 Version comparison: '\(newVersion)' vs '\(currentVersion)'")
        print("   Cleaned: '\(cleanNew)' vs '\(cleanCurrent)'")
        
        // If base versions are identical, no update needed
        if cleanNew == cleanCurrent {
            print("   ✅ Versions are identical - no update needed")
            return false
        }
        // If current is a prefix of new (as a full version component), treat as equal
        if cleanNew.hasPrefix(cleanCurrent) {
            let idx = cleanNew.index(cleanNew.startIndex, offsetBy: cleanCurrent.count)
            if idx == cleanNew.endIndex || cleanNew[idx] == "." {
                print("   ✅ Current version is a prefix of new version - treat as up to date")
                return false
            }
        }
        let result = compareVersions(cleanNew, cleanCurrent) > 0
        print("   \(result ? "✅" : "❌") New version is \(result ? "newer" : "not newer")")
        return result
    }
    
    private static func cleanVersion(_ version: String) -> String {
        var clean = version
        
        // Remove common prefixes
        clean = clean.replacingOccurrences(of: "v", with: "", options: [.caseInsensitive, .anchored])
        clean = clean.replacingOccurrences(of: "Build ", with: "", options: [.caseInsensitive])
        clean = clean.replacingOccurrences(of: "Version ", with: "", options: [.caseInsensitive])
        
        // Special handling for Android Studio versions with embedded build numbers
        // e.g. "2024.2.1.11" or "2024.2.1 Patch 2"
        clean = clean.replacingOccurrences(of: " Patch ", with: ".")
        
        // Handle versions like "6.5.3 (58803)" vs "6.5.3.58803"
        // Normalize to same format
        clean = clean.replacingOccurrences(of: " (", with: ".")
        clean = clean.replacingOccurrences(of: ")", with: "")
        
        // Remove build numbers after dash (e.g., "3.5.0-3d21337d" -> "3.5.0")
        if let dashRange = clean.range(of: "-") {
            clean = String(clean[..<dashRange.lowerBound])
        }
        
        // Remove build numbers in parentheses (e.g., "20.4.0 (55980)" -> "20.4.0")
        if let parenRange = clean.range(of: " (") {
            clean = String(clean[..<parenRange.lowerBound])
        }
        
        // Remove any trailing periods
        while clean.hasSuffix(".") {
            clean.removeLast()
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func compareVersions(_ v1: String, _ v2: String) -> Int {
        let v1Parts = v1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = v2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(v1Parts.count, v2Parts.count)
        
        for i in 0..<maxCount {
            let v1Part = i < v1Parts.count ? v1Parts[i] : 0
            let v2Part = i < v2Parts.count ? v2Parts[i] : 0
            
            if v1Part > v2Part { return 1 }
            if v1Part < v2Part { return -1 }
        }
        
        return 0
    }
}
