//
//  DaemonCommunicator.swift
//  PatchMaster
//
//  Created by Somesh Pathak on 02/07/2025.
//

import Foundation
import AppKit

public class DaemonCommunicator {
    static let shared = DaemonCommunicator()
    private let ipcDirectory = "/tmp/patchmaster-ipc"
    
    private init() {
        setupIPC()
    }
    
    private func setupIPC() {
        let requestsDir = "\(ipcDirectory)/requests"
        let responsesDir = "\(ipcDirectory)/responses"
        let progressDir = "\(ipcDirectory)/progress"
        
        try? FileManager.default.createDirectory(atPath: ipcDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: requestsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: responsesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: progressDir, withIntermediateDirectories: true)
    }
    
    private func sendRequest(_ request: DaemonRequest) async throws -> DaemonResponse {
        let requestsDir = "\(ipcDirectory)/requests"
        let responsesDir = "\(ipcDirectory)/responses"
        let requestPath = "\(requestsDir)/\(request.id).json"
        let responsePath = "\(responsesDir)/\(request.id).json"
        
        try? FileManager.default.removeItem(atPath: requestPath)
        try? FileManager.default.removeItem(atPath: responsePath)
        
        print("📡 Sending request \(request.id) (\(request.type))")
        
        let requestData = try JSONEncoder().encode(request)
        let tempPath = "\(requestPath).tmp"
        try requestData.write(to: URL(fileURLWithPath: tempPath))
        try FileManager.default.moveItem(atPath: tempPath, toPath: requestPath)
        
        print("✅ Request file written: \(requestPath)")
        
        let maxWaitTime = getTimeoutForRequest(request.type)
        let startTime = Date()
        let checkInterval: TimeInterval = 0.5
        
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            if FileManager.default.fileExists(atPath: responsePath) {
                do {
                    let responseData = try Data(contentsOf: URL(fileURLWithPath: responsePath))
                    let response = try JSONDecoder().decode(DaemonResponse.self, from: responseData)
                    
                    try? FileManager.default.removeItem(atPath: responsePath)
                    print("✅ Received response for \(request.id)")
                    
                    return response
                } catch {
                    print("❌ Failed to parse response: \(error)")
                }
            }
            
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        try? FileManager.default.removeItem(atPath: requestPath)
        throw NSError(domain: "DaemonCommunicator", code: 408, userInfo: [
            NSLocalizedDescriptionKey: "Request timeout after \(Int(maxWaitTime)) seconds"
        ])
    }
    
    private func getTimeoutForRequest(_ type: DaemonRequest.RequestType) -> Double {
        switch type {
        case .downloadApp: return 900.0      // 15 minutes
        case .installApp: return 600.0       // 10 minutes
        case .checkUpdates: return 120.0     // 2 minutes
        case .scanApps: return 60.0          // 1 minute
        case .cancelDownload: return 10.0    // 10 seconds
        case .installNativeApp: return 300.0 // 5 minutes
        }
    }
    
    func checkForUpdates() async throws -> [MockAppUpdate] {
        print("🔍 Starting update check...")
        let request = DaemonRequest(type: .checkUpdates, data: nil)
        let response = try await sendRequest(request)
        
        if response.success, let data = response.data {
            let updates = try JSONDecoder().decode([MockAppUpdate].self, from: data)
            print("✅ Update check completed: \(updates.count) updates")
            return updates
        } else {
            let error = response.error ?? "Unknown error"
            print("❌ Update check failed: \(error)")
            throw NSError(domain: "DaemonCommunicator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: error
            ])
        }
    }
    
    func installApp(from fileURL: URL, appName: String) async throws {
        let request = DaemonRequest(
            type: .installApp,
            data: ["fileURL": fileURL.path, "appName": appName]
        )
        let response = try await sendRequest(request)
        
        if !response.success {
            throw NSError(domain: "DaemonCommunicator", code: 2, userInfo: [
                NSLocalizedDescriptionKey: response.error ?? "Installation failed"
            ])
        }
    }
    
    func installAppWithResult(from fileURL: URL, appName: String) async -> DaemonResponse {
        let request = DaemonRequest(
            type: .installApp,
            data: ["fileURL": fileURL.path, "appName": appName]
        )
        do {
            let response = try await sendRequest(request)
            return response
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
    }
    
    func downloadAndInstallApp(from downloadURL: String, appName: String, progressCallback: @escaping (Double) -> Void) async throws {
        print("📥 Starting download: \(appName)")
        
        progressCallback(0.05)
        let downloadRequest = DaemonRequest(
            type: .downloadApp,
            data: ["downloadURL": downloadURL, "appName": appName]
        )
        
        let progressTask = Task {
            await monitorDownloadProgress(requestId: downloadRequest.id, appName: appName, progressCallback: progressCallback)
        }
        
        let downloadResponse = try await sendRequest(downloadRequest)
        progressTask.cancel()
        
        if !downloadResponse.success {
            throw NSError(domain: "DaemonCommunicator", code: 3, userInfo: [
                NSLocalizedDescriptionKey: downloadResponse.error ?? "Download failed"
            ])
        }
        
        guard let downloadData = downloadResponse.data,
              let downloadResult = try? JSONDecoder().decode([String: String].self, from: downloadData),
              let tempFileURL = downloadResult["tempFileURL"] else {
            throw NSError(domain: "DaemonCommunicator", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to get download file path"
            ])
        }
        
        progressCallback(0.90)
        
        let installRequest = DaemonRequest(
            type: .installApp,
            data: ["fileURL": tempFileURL, "appName": appName]
        )
        
        let installResponse = try await sendRequest(installRequest)
        
        if !installResponse.success {
            throw NSError(domain: "DaemonCommunicator", code: 5, userInfo: [
                NSLocalizedDescriptionKey: installResponse.error ?? "Installation failed"
            ])
        }
        
        progressCallback(1.0)
    }
    
    func downloadAndInstallAppWithResult(from downloadURL: String, appName: String, progressCallback: @escaping (Double) -> Void) async -> DaemonResponse {
        print("📥 Starting download: \(appName)")
        progressCallback(0.05)
        let downloadRequest = DaemonRequest(
            type: .downloadApp,
            data: ["downloadURL": downloadURL, "appName": appName]
        )
        do {
            let progressTask = Task {
                await monitorDownloadProgress(requestId: downloadRequest.id, appName: appName, progressCallback: progressCallback)
            }
            let downloadResponse = try await sendRequest(downloadRequest)
            progressTask.cancel()
            if !downloadResponse.success {
                return downloadResponse
            }
            guard let downloadData = downloadResponse.data,
                  let downloadResult = try? JSONDecoder().decode([String: String].self, from: downloadData),
                  let tempFileURL = downloadResult["tempFileURL"] else {
                return DaemonResponse(success: false, data: nil, error: "Failed to get download file path")
            }
            progressCallback(0.90)
            let installRequest = DaemonRequest(
                type: .installApp,
                data: ["fileURL": tempFileURL, "appName": appName]
            )
            let installResponse = try await sendRequest(installRequest)
            if !installResponse.success {
                return installResponse
            }
            progressCallback(1.0)
            return installResponse
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
    }
    
    private func monitorDownloadProgress(requestId: String, appName: String, progressCallback: @escaping (Double) -> Void) async {
        let progressDir = "\(ipcDirectory)/progress"
        let progressFile = "\(progressDir)/\(requestId).json"
        
        while !Task.isCancelled {
            if FileManager.default.fileExists(atPath: progressFile) {
                do {
                    let progressData = try Data(contentsOf: URL(fileURLWithPath: progressFile))
                    if let progressInfo = try JSONSerialization.jsonObject(with: progressData) as? [String: Any],
                       let progress = progressInfo["progress"] as? Double {
                        
                        let scaledProgress = 0.05 + (progress * 0.75)
                        await MainActor.run {
                            progressCallback(scaledProgress)
                        }
                    }
                } catch {
                    // Ignore parsing errors
                }
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        try? FileManager.default.removeItem(atPath: progressFile)
    }
    
    func cancelDownload(downloadURL: String) async throws {
        let request = DaemonRequest(
            type: .cancelDownload,
            data: ["downloadURL": downloadURL]
        )
        
        let response = try await sendRequest(request)
        
        if !response.success {
            throw NSError(domain: "DaemonCommunicator", code: 6, userInfo: [
                NSLocalizedDescriptionKey: response.error ?? "Cancel failed"
            ])
        }
    }
    
    func installNativeApp(bundleId: String, appName: String) async throws {
        let request = DaemonRequest(
            type: .installNativeApp,
            data: ["bundleId": bundleId]
        )
        
        let response = try await sendRequest(request)
        
        if !response.success {
            throw NSError(domain: "DaemonCommunicator", code: 7, userInfo: [
                NSLocalizedDescriptionKey: response.error ?? "Native update failed"
            ])
        }
    }
    
    func installNativeAppWithResult(bundleId: String, appName: String) async -> DaemonResponse {
        let request = DaemonRequest(
            type: .installNativeApp,
            data: ["bundleId": bundleId, "appName": appName]
        )
        do {
            let response = try await sendRequest(request)
            return response
        } catch {
            return DaemonResponse(success: false, data: nil, error: error.localizedDescription)
        }
    }
}

struct DaemonRequest: Codable {
    enum RequestType: String, Codable {
        case scanApps
        case checkUpdates
        case installApp
        case downloadApp
        case cancelDownload
        case installNativeApp
    }
    
    var id: String
    let type: RequestType
    let data: [String: String]?
    
    init(type: RequestType, data: [String: String]?) {
        self.id = UUID().uuidString
        self.type = type
        self.data = data
    }
}

struct DaemonResponse: Codable {
    let success: Bool
    let data: Data?
    let error: String?
}

struct MockInstalledApp {
    let bundleId: String
    let version: String
    let path: String
    let icon: NSImage?
}

public struct MockAppUpdate: Codable {
    let appName: String
    let currentVersion: String
    let newVersion: String
    let downloadURL: String?
    let source: String
    let installedBundleId: String
    
    var installedAppIcon: NSImage? {
        return IconLoader.loadIcon(for: installedBundleId)
    }
}

class IconLoader {
    private static let iconCache = NSCache<NSString, NSImage>()
    
    static func loadIcon(for bundleId: String) -> NSImage? {
        if let cachedIcon = iconCache.object(forKey: bundleId as NSString) {
            return cachedIcon
        }
        
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            let resizedIcon = resizeIcon(icon, to: NSSize(width: 64, height: 64))
            iconCache.setObject(resizedIcon, forKey: bundleId as NSString)
            return resizedIcon
        }
        
        return NSImage(named: "NSDefaultApplicationIcon")
    }
    
    private static func resizeIcon(_ icon: NSImage, to size: NSSize) -> NSImage {
        let resizedIcon = NSImage(size: size)
        resizedIcon.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        resizedIcon.unlockFocus()
        return resizedIcon
    }
}
