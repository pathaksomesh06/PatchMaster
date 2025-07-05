//
//  NativeUpdateChecker.swift
//  PatchMasterDaemon
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

class NativeUpdateChecker {
    
    // Registry of apps that support native updates
    static let nativeUpdateRegistry: [String: NativeUpdateConfig] = [
        "com.parallels.desktop.console": NativeUpdateConfig(
            appName: "Parallels Desktop",
            checkCommand: "/Applications/Parallels\\ Desktop.app/Contents/MacOS/prlctl update",
            installCommand: "/Applications/Parallels\\ Desktop.app/Contents/MacOS/prlctl update --install",
            versionCheckCommand: "/Applications/Parallels\\ Desktop.app/Contents/MacOS/prlctl version",
            requiresAdmin: false // prlctl can run without admin for checking
        )
    ]
    
    static func findUpdatesForInstalledApps(_ installedApps: [InstalledApp]) async throws -> [AppUpdate] {
        var updates: [AppUpdate] = []
        
        print("\n=== Native Update Check ===")
        
        for app in installedApps {
            if let config = nativeUpdateRegistry[app.bundleId] {
                print("\nChecking native updates for: \(config.appName)")
                print("  Bundle ID: \(app.bundleId)")
                print("  Installed: \(app.version)")
                
                do {
                    if let availableVersion = try await checkForUpdate(app: app, config: config) {
                        print("  ✅ Update available via native mechanism!")
                        print("  New version: \(availableVersion)")
                        
                        let update = AppUpdate.fromNative(
                            appName: config.appName,
                            currentVersion: app.version,
                            newVersion: availableVersion,
                            installedAppIcon: app.icon,
                            installedBundleId: app.bundleId,
                            updateCommand: config.installCommand
                        )
                        updates.append(update)
                    } else {
                        print("  ✅ Up to date")
                    }
                } catch {
                    print("  ❌ Failed to check native updates: \(error.localizedDescription)")
                }
            }
        }
        
        print("\nNative checker found \(updates.count) updates")
        return updates
    }
    
    private static func checkForUpdate(app: InstalledApp, config: NativeUpdateConfig) async throws -> String? {
        // For Parallels, run prlctl update to check for available updates
        let output = try await runCommand(config.checkCommand)
        
        // Parse the output to determine if updates are available
        // The command will typically show available versions or indicate no updates
        if let newVersion = parseUpdateOutput(output, currentVersion: app.version, appName: config.appName) {
            return newVersion
        }
        
        return nil
    }
    
    private static func parseUpdateOutput(_ output: String, currentVersion: String, appName: String) -> String? {
            print("  🔍 Parsing prlctl update output:")
            print("  Raw output: \(output)")
            
            let lowercasedOutput = output.lowercased()
            
            // Check if already up to date
            if lowercasedOutput.contains("no updates") ||
               lowercasedOutput.contains("up to date") ||
               lowercasedOutput.contains("already installed") ||
               lowercasedOutput.contains("latest version") {
                print("  ✅ Parallels Desktop is already up to date")
                return nil
            }
            
            // Look for specific update availability patterns
            if lowercasedOutput.contains("new version") ||
               lowercasedOutput.contains("update available") ||
               lowercasedOutput.contains("can be updated") {
                
                // Try to extract version number
                let versionPattern = #"(\d+\.\d+\.\d+(?:-\d+)?)"#
                if let regex = try? NSRegularExpression(pattern: versionPattern),
                   let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                    if let versionRange = Range(match.range, in: output) {
                        let detectedVersion = String(output[versionRange])
                        print("  📦 Found version in output: \(detectedVersion)")
                        
                        // Only return if genuinely newer
                        if isVersionNewer(detectedVersion, than: currentVersion) {
                            return detectedVersion
                        }
                    }
                }
                
                // If we can't extract version but know update is available
                print("  📦 Update available but version not specified")
                return "Latest"
            }
            
            // No update detected
            print("  ℹ️ No update detected in prlctl output")
            return nil
        }
    
    private static func isVersionNewer(_ newVersion: String, than currentVersion: String) -> Bool {
        // Simple version comparison - this could be enhanced
        let newComponents = newVersion.components(separatedBy: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.components(separatedBy: ".").compactMap { Int($0) }
        
        let maxLength = max(newComponents.count, currentComponents.count)
        
        for i in 0..<maxLength {
            let newComponent = i < newComponents.count ? newComponents[i] : 0
            let currentComponent = i < currentComponents.count ? currentComponents[i] : 0
            
            if newComponent > currentComponent {
                return true
            } else if newComponent < currentComponent {
                return false
            }
        }
        
        return false
    }
    
    private static func runCommand(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", command]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
            
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // Install update using native mechanism
    static func installNativeUpdate(for bundleId: String) async throws {
        guard let config = nativeUpdateRegistry[bundleId] else {
            throw NSError(domain: "NativeUpdateChecker", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "No native update configuration found for \(bundleId)"])
        }
        
        print("🚀 Installing native update for \(config.appName)")
        print("   Command: \(config.installCommand)")
        
        let output = try await runCommand(config.installCommand)
        print("   Output: \(output)")
        
        if output.lowercased().contains("error") || output.lowercased().contains("failed") {
            throw NSError(domain: "NativeUpdateChecker", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Native update failed: \(output)"])
        }
        
        print("✅ Native update completed successfully")
    }
}

// Configuration for apps that support native updates
struct NativeUpdateConfig {
    let appName: String
    let checkCommand: String
    let installCommand: String
    let versionCheckCommand: String
    let requiresAdmin: Bool
} 
