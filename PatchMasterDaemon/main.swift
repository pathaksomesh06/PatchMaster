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

// Global timer reference to prevent deallocation
var requestMonitorTimer: DispatchSourceTimer?

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
        
        // Create with permissions in one step
        try FileManager.default.createDirectory(atPath: ipcDirectory, withIntermediateDirectories: true, attributes: attributes)
        try FileManager.default.createDirectory(atPath: requestsDir, withIntermediateDirectories: true, attributes: attributes)
        try FileManager.default.createDirectory(atPath: responsesDir, withIntermediateDirectories: true, attributes: attributes)
        try FileManager.default.createDirectory(atPath: progressDir, withIntermediateDirectories: true, attributes: attributes)
        
        // Force permissions with chmod command for reliability
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["-R", "777", ipcDirectory]
        try chmod.run()
        chmod.waitUntilExit()
        
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
            // Report initial progress
            UpdateChecker.writeProgress(requestId: request.id, status: "Scanning installed apps...")
            
            // Start a heartbeat task to keep progress file updated during long operations
            let heartbeatTask = Task {
                while !Task.isCancelled {
                    // Touch the progress file to keep it fresh
                    let progressFile = "\(progressDir)/\(request.id).json"
                    if FileManager.default.fileExists(atPath: progressFile) {
                        // File exists, just update timestamp
                        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: progressFile)
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // Every 10 seconds
                }
            }
            
            let installedApps = AppScanner.scanInstalledApps()
            heartbeatTask.cancel()
            
            let updates = try await UpdateChecker.checkForUpdates(installedApps: installedApps, requestId: request.id)
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
        
        print("🚀 Downloading \(appName) from: \(downloadURL)")
        
        do {
            // Use the enhanced download manager for better progress tracking
            let downloadResult = try await DownloadManager.shared.downloadWithProgress(
                from: downloadURL,
                appName: appName,
                requestId: request.id
            )
            
            print("✅ Downloaded to: \(downloadResult.tempFileURL) as .\(downloadResult.fileExtension)")
            
            let responseData = try JSONEncoder().encode(["tempFileURL": downloadResult.tempFileURL])
            return DaemonResponse(success: true, data: responseData, error: nil)
        } catch {
            print("❌ Download failed: \(error.localizedDescription)")
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

// Process a single request file - using semaphore to bridge async/sync
func processRequestFile(_ fileName: String) {
    let fileManager = FileManager.default
    let requestPath = "\(requestsDir)/\(fileName)"
    let responsePath = "\(responsesDir)/\(fileName)"
    
    print("📨 Found request file: \(fileName)")
    
    do {
        let requestData = try Data(contentsOf: URL(fileURLWithPath: requestPath))
        let request = try JSONDecoder().decode(DaemonRequest.self, from: requestData)
        
        print("🔄 Processing request: \(request.type) with ID: \(request.id)")
        
        // Remove the request file immediately to prevent reprocessing
        try? fileManager.removeItem(atPath: requestPath)
        
        // Use a dedicated queue for async processing
        DispatchQueue.global(qos: .userInitiated).async {
            let semaphore = DispatchSemaphore(value: 0)
            var response: DaemonResponse?
            
            Task {
                response = await processRequest(request)
                semaphore.signal()
            }
            
            // Wait for async processing to complete (with timeout)
            let result = semaphore.wait(timeout: .now() + 600) // 10 minute timeout
            
            if result == .timedOut {
                print("❌ Request timed out: \(request.id)")
                response = DaemonResponse(success: false, data: nil, error: "Request timed out")
            }
            
            guard let finalResponse = response else {
                print("❌ No response generated for: \(request.id)")
                return
            }
            
            do {
                let responseData = try JSONEncoder().encode(finalResponse)
                
                print("📝 Writing response to: \(responsePath)")
                try responseData.write(to: URL(fileURLWithPath: responsePath))
                
                // Set world-readable permissions
                let chmod = Process()
                chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmod.arguments = ["666", responsePath]
                try chmod.run()
                chmod.waitUntilExit()
                
                print("✅ Processed request \(request.id) - Success: \(finalResponse.success)")
            } catch {
                print("❌ Error writing response: \(error)")
            }
        }
        
    } catch {
        print("❌ Error parsing request \(fileName): \(error)")
        // Remove malformed request
        try? fileManager.removeItem(atPath: requestPath)
    }
}

// Monitor for requests using Timer (more reliable than async Task for daemons)
func startRequestMonitor() {
    let fileManager = FileManager.default
    
    print("📡 Starting request monitor on \(requestsDir)")
    
    // Use a DispatchSourceTimer for reliable polling
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
    timer.schedule(deadline: .now(), repeating: .seconds(1))
    timer.setEventHandler {
        do {
            let requestFiles = try fileManager.contentsOfDirectory(atPath: requestsDir)
            let jsonFiles = requestFiles.filter { $0.hasSuffix(".json") }
            
            if !jsonFiles.isEmpty {
                print("📬 Found \(jsonFiles.count) request(s)")
            }
            
            for fileName in jsonFiles {
                processRequestFile(fileName)
            }
        } catch {
            print("❌ Error listing requests: \(error)")
        }
    }
    timer.resume()
    
    // Store in global to prevent deallocation
    requestMonitorTimer = timer
}

print("PatchMaster Daemon starting...")
print("Setting up IPC...")
setupIPC()
print("Starting request monitor...")
startRequestMonitor()

print("Daemon running - waiting for requests...")
fflush(stdout)
fflush(stderr)

// Keep daemon alive using dispatchMain (standard for daemons using GCD)
dispatchMain()
