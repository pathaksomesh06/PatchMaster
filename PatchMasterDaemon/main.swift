//
//  main.swift
//  PatchMasterDaemon
//
//  Created by Somesh Pathak on 02/07/2025.
//

//
//  main.swift
//  PatchMasterDaemon
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation

// IPC Configuration
let ipcDirectory = "/tmp/patchmaster-ipc"
let requestsDir = "\(ipcDirectory)/requests"
let responsesDir = "\(ipcDirectory)/responses"
let progressDir = "\(ipcDirectory)/progress"

// Create IPC directories
func setupIPC() {
    do {
        // Create directories
        try FileManager.default.createDirectory(atPath: ipcDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: requestsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: responsesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: progressDir, withIntermediateDirectories: true)
        
        // Set proper permissions: 755 for directories, allowing read/write for owner and group
        // This allows both root daemon and user app to access
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o777  // rwxrwxrwx - allow all users to read/write
        ]
        
        try FileManager.default.setAttributes(attributes, ofItemAtPath: ipcDirectory)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: requestsDir)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: responsesDir)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: progressDir)
        
        print("✅ IPC directories created with proper permissions")
        print("   \(ipcDirectory)")
        print("   \(requestsDir)")
        print("   \(responsesDir)") 
        print("   \(progressDir)")
        
    } catch {
        print("❌ Failed to setup IPC directories: \(error)")
    }
}

// Request/Response structures
struct DaemonRequest: Codable {
    enum RequestType: String, Codable {
        case scanApps
        case checkUpdates
        case installApp
        case downloadApp
        case cancelDownload
        case installNativeApp
    }
    
    let id: String
    let type: RequestType
    let data: [String: String]?
}

struct DaemonResponse: Codable {
    let success: Bool
    let data: Data?
    let error: String?
}

// Process requests
func processRequest(_ request: DaemonRequest) async -> DaemonResponse {
    print("Processing request: \(request.type) with ID: \(request.id)")
    
    switch request.type {
    case .scanApps:
        do {
            let apps = AppScanner.scanInstalledApps()
            let data = try JSONEncoder().encode(apps)
            return DaemonResponse(success: true, data: data, error: nil)
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
        
    case .checkUpdates:
        do {
            let installedApps = AppScanner.scanInstalledApps()
            let updates = try await UpdateChecker.checkForUpdates(installedApps: installedApps)
            // Convert to simplified format for main app compatibility
            let simpleUpdates = updates.map { SimpleAppUpdate(from: $0) }
            let data = try JSONEncoder().encode(simpleUpdates)
            return DaemonResponse(success: true, data: data, error: nil)
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
        
    case .installApp:
        guard let fileURLString = request.data?["fileURL"],
              let appName = request.data?["appName"] else {
            return DaemonResponse(success: false, data: nil, error: "Missing fileURL or appName")
        }
        
        do {
            let fileURL = URL(fileURLWithPath: fileURLString)
            print("🚀 Starting installation of \(appName) from \(fileURL.path)")
            try await AppInstaller.install(from: fileURL, appName: appName)
            
            // Give the system time to register the newly installed app
            print("⏳ Waiting for system to register \(appName)...")
            try await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds for better detection
            
            // Force refresh system caches
            print("🔄 Force refreshing system caches...")
            AppScanner.clearLaunchServicesCache()
            try await Task.sleep(nanoseconds: 3_000_000_000) // Additional 3 seconds for cache refresh
            
            print("✅ Installation process completed for \(appName)")
            
            // Debug version detection after installation
            if let bundleId = request.data?["bundleId"] {
                print("🔍 Running post-installation debug for bundle ID: \(bundleId)")
                UpdateChecker.debugVersionDetection(for: bundleId, appName: appName)
            } else {
                print("🔍 Running post-installation debug without bundle ID")
                // Try to find bundle ID by scanning for the app
                let installedApps = AppScanner.scanInstalledApps()
                let cleanAppName = appName.replacingOccurrences(of: ".app", with: "")
                
                for app in installedApps {
                    let installedAppName = (app.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                    if installedAppName.lowercased().contains(cleanAppName.lowercased()) ||
                       cleanAppName.lowercased().contains(installedAppName.lowercased()) {
                        print("🎯 Found matching app: \(installedAppName) with bundle ID: \(app.bundleId)")
                        UpdateChecker.debugVersionDetection(for: app.bundleId, appName: installedAppName)
                        break
                    }
                }
            }
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: fileURL)
            
            return DaemonResponse(success: true, data: nil, error: nil)
        } catch {
            print("❌ Installation failed for \(appName): \(error.localizedDescription)")
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
        
    case .downloadApp:
        guard let downloadURL = request.data?["downloadURL"],
              let appName = request.data?["appName"] else {
            return DaemonResponse(success: false, data: nil, error: "Missing downloadURL or appName")
        }
        
        do {
            // Use the enhanced download manager for better progress tracking
            let downloadResult = try await DownloadManager.shared.downloadWithProgress(
                from: downloadURL,
                appName: appName,
                requestId: request.id
            )
            
            let responseData = try JSONEncoder().encode(["tempFileURL": downloadResult.tempFileURL])
            return DaemonResponse(success: true, data: responseData, error: nil)
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
        
    case .cancelDownload:
        guard let downloadURL = request.data?["downloadURL"] else {
            return DaemonResponse(success: false, data: nil, error: "Missing downloadURL")
        }
        
        do {
            DownloadManager.shared.cancel(urlString: downloadURL)
            return DaemonResponse(success: true, data: nil, error: nil)
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
        
    case .installNativeApp:
        guard let bundleId = request.data?["bundleId"] else {
            return DaemonResponse(success: false, data: nil, error: "Missing bundleId for native app installation")
        }
        
        do {
            print("🚀 Starting native update for bundle ID: \(bundleId)")
            try await NativeUpdateChecker.installNativeUpdate(for: bundleId)
            print("✅ Native update completed successfully")
            
            // Debug version detection after native update
            print("🔍 Running post-update debug for native app: \(bundleId)")
            let installedApps = AppScanner.scanInstalledApps()
            if let app = installedApps.first(where: { $0.bundleId == bundleId }) {
                let appName = (app.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                UpdateChecker.debugVersionDetection(for: bundleId, appName: appName)
            }
            
            return DaemonResponse(success: true, data: nil, error: nil)
        } catch {
            print("❌ Native update failed: \(error.localizedDescription)")
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
    }
}

// Monitor for requests
func startRequestMonitor() {
    let fileManager = FileManager.default
    
    Task {
        while true {
            do {
                let requestFiles = try fileManager.contentsOfDirectory(atPath: requestsDir)
                
                for fileName in requestFiles where fileName.hasSuffix(".json") {
                    let requestPath = "\(requestsDir)/\(fileName)"
                    let responsePath = "\(responsesDir)/\(fileName)"
                    
                    do {
                        let requestData = try Data(contentsOf: URL(fileURLWithPath: requestPath))
                        let request = try JSONDecoder().decode(DaemonRequest.self, from: requestData)
                        
                        let response = await processRequest(request)
                        let responseData = try JSONEncoder().encode(response)
                        try responseData.write(to: URL(fileURLWithPath: responsePath))
                        
                        // Remove processed request
                        try fileManager.removeItem(atPath: requestPath)
                        
                        print("Processed request \(request.id) - Success: \(response.success)")
                        
                    } catch {
                        print("Error processing request \(fileName): \(error)")
                        // Remove malformed request
                        try? fileManager.removeItem(atPath: requestPath)
                    }
                }
                
                // Check every second
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
            } catch {
                print("Error monitoring requests: \(error)")
                try await Task.sleep(nanoseconds: 5_000_000_000) // Wait 5 seconds on error
            }
        }
    }
}

print("PatchMaster Daemon starting...")
setupIPC()
startRequestMonitor()

// Keep daemon running
RunLoop.main.run()
