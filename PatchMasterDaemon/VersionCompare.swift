//
//  VersionCompare.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//


import Foundation

class VersionCompare {
    /// Pre-release identifiers that indicate unstable versions
    private static let prereleaseIdentifiers = [
        "preview", "beta", "alpha", "rc", "dev", "nightly", "canary", 
        "snapshot", "insider", "pre", "test", "experimental"
    ]
    
    /// Clean version string for display/comparison
    /// Removes build metadata, dashes, and padding
    static func cleanVersionForDisplay(_ version: String) -> String {
        return cleanVersion(version)
    }
    
    /// Check if a version string contains pre-release identifiers
    static func isPreReleaseVersion(_ version: String) -> Bool {
        let lowerVersion = version.lowercased()
        return prereleaseIdentifiers.contains { lowerVersion.contains($0) }
    }
    
    static func isNewer(_ newVersion: String, than currentVersion: String) -> Bool {
        print("🔍 Version comparison: '\(newVersion)' vs '\(currentVersion)'")
        
        // Skip pre-release versions unless current is also pre-release
        if isPreReleaseVersion(newVersion) && !isPreReleaseVersion(currentVersion) {
            print("   ⏭️ Skipping pre-release version: \(newVersion)")
            return false
        }
        
        // Strip build numbers and compare base versions only
        let cleanNew = cleanVersion(newVersion)
        let cleanCurrent = cleanVersion(currentVersion)
        
        print("   Cleaned: '\(cleanNew)' vs '\(cleanCurrent)'")
        
        // If base versions are identical, no update needed
        if cleanNew == cleanCurrent {
            print("   ✅ Versions are identical - no update needed")
            return false
        }
        
        // Early check: if versions differ only by trailing short numeric segments, treat as equal
        if isEffectivelySameVersion(cleanNew, cleanCurrent) {
            print("   ✅ Versions are effectively the same (trailing build-only difference)")
            return false
        }
        
        // Special handling for cases where current version is clearly older
        // but the version formats are very different
        if isClearlyOlder(cleanCurrent, than: cleanNew) {
            print("   ✅ Current version is clearly older based on format analysis")
            return true
        }
        
        // If current is a prefix of new (as a full version component), treat as equal when suffix is minor/build-only
        if cleanNew.hasPrefix(cleanCurrent) {
            let idx = cleanNew.index(cleanNew.startIndex, offsetBy: cleanCurrent.count)
            if idx == cleanNew.endIndex || cleanNew[idx] == "." {
                let remaining = String(cleanNew[idx...]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if remaining.isEmpty || isMinorVersionDifference(remaining) {
                    print("   ✅ Current version is a prefix of new version - treat as up to date")
                    return false
                }
            }
        }
        
        let result = compareVersions(cleanNew, cleanCurrent) > 0
        print("   \(result ? "✅" : "❌") New version is \(result ? "newer" : "not newer")")
        return result
    }

    static func isEffectivelySameVersion(_ newVersion: String, _ currentVersion: String) -> Bool {
        let newParts = newVersion.split(separator: ".").map { String($0) }
        let curParts = currentVersion.split(separator: ".").map { String($0) }
        
        if newParts == curParts { return true }
        
        // Determine which is longer and which is shorter
        let (longerParts, shorterParts) = newParts.count > curParts.count 
            ? (newParts, curParts) 
            : (curParts, newParts)
        
        // If longer version starts with all components of shorter version
        guard longerParts.starts(with: shorterParts) else { return false }
        
        // Check if all extra trailing segments are short numeric build numbers or padded zeros
        let extraParts = longerParts.suffix(longerParts.count - shorterParts.count)
        let allExtraPartsAreBuilds = extraParts.allSatisfy { part in
            // Accept numeric parts that are:
            // 1. 4 digits or less (typical build numbers)
            // 2. Padded zeros (0001, 0002, 0000)
            // 3. Single/double digit numbers (like .2, .8, .18)
            guard part.allSatisfy({ $0.isNumber }) else { return false }
            
            // If it's all zeros or padded zeros, it's just padding
            if part.allSatisfy({ $0 == "0" }) { return true }
            
            // Accept up to 4-digit numeric parts
            if part.count <= 4 { return true }
            
            // Reject longer numeric strings (likely meaningful version components)
            return false
        }
        
        if allExtraPartsAreBuilds {
            print("   🔍 Treating as same: trailing build segments \(extraParts.joined(separator: ".")) ignored")
            return true
        }
        
        return false
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
        
        // Remove build numbers after dash - these are NOT version components
        // Examples: "26.2.0-57363" -> "26.2.0", "1.2.3-abc123def" -> "1.2.3"
        if let dashRange = clean.range(of: "-") {
            clean = String(clean[..<dashRange.lowerBound])
        }
        
        // Remove any trailing periods
        while clean.hasSuffix(".") {
            clean.removeLast()
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func isClearlyOlder(_ current: String, than new: String) -> Bool {
        // Handle cases where version formats are completely different
        // but we can still determine which is newer
        
        // Case 1: Chrome-style versioning (138.x.x.x vs 1.x.x.x)
        if current.contains(".") && new.contains(".") {
            let currentParts = current.split(separator: ".").compactMap { Int($0) }
            let newParts = new.split(separator: ".").compactMap { Int($0) }
            
            if currentParts.count >= 4 && newParts.count >= 4 {
                // If current starts with a large number (like 138) and new starts with 1,
                // but the rest of the version components are similar, new is likely newer
                if currentParts[0] > 100 && newParts[0] <= 10 {
                    let currentRest = Array(currentParts[1...])
                    let newRest = Array(newParts[1...])
                    if currentRest.count >= 3 && newRest.count >= 3 {
                        // Compare the last 3 components
                        let currentSuffix = Array(currentRest.suffix(3))
                        let newSuffix = Array(newRest.suffix(3))
                        if currentSuffix == newSuffix {
                            return true // New version is newer
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    private static func isMinorVersionDifference(_ remaining: String) -> Bool {
        // Check if the remaining part represents a minor version difference
        // (like build numbers, patch versions, etc.)
        
        // If it's just numbers, it's likely a build number
        if remaining.allSatisfy({ $0.isNumber }) {
            return true
        }
        
        // If it's a small number (like .1, .2, etc.), it's likely a patch
        if remaining.count <= 3 && remaining.allSatisfy({ $0.isNumber || $0 == "." }) {
            return true
        }
        
        return false
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
