//
//  DownloadManager.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//


import Foundation

struct DownloadResult {
    let tempFileURL: String
    let fileExtension: String
}

class DownloadManager: NSObject {
    static let shared = DownloadManager()
    private var activeDownloads: [URL: URLSessionDownloadTask] = [:]
    private var progressHandlers: [URL: (Double) -> Void] = [:]
    private var completionHandlers: [URL: (Result<URL, Error>) -> Void] = [:]
    private var requestIds: [URL: String] = [:]
    
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    
    // Enhanced download method for daemon use with progress tracking via IPC
    func downloadWithProgress(from urlString: String, appName: String, requestId: String) async throws -> DownloadResult {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL: \(urlString)"])
        }
        
        print("📥 Starting download for \(appName) from \(urlString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            // Store request ID for progress updates
            requestIds[url] = requestId
            
            // Set up progress handler to write to IPC
            progressHandlers[url] = { progress in
                self.writeProgressUpdate(requestId: requestId, progress: progress, appName: appName)
            }
            
            // Set up completion handler
            completionHandlers[url] = { result in
                switch result {
                case .success(let tempURL):
                    // Detect file extension
                    var fileExtension = "dmg" // default
                    let urlExtension = url.pathExtension.lowercased()
                    if !urlExtension.isEmpty {
                        fileExtension = urlExtension
                    }
                    
                    // Create final file with proper extension
                    let finalURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(appName).\(fileExtension)")
                    
                    do {
                        try? FileManager.default.removeItem(at: finalURL)
                        try FileManager.default.moveItem(at: tempURL, to: finalURL)
                        
                        print("📦 Downloaded \(appName) as \(fileExtension) file: \(finalURL.path)")
                        
                        let downloadResult = DownloadResult(
                            tempFileURL: finalURL.path,
                            fileExtension: fileExtension
                        )
                        continuation.resume(returning: downloadResult)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            let task = session.downloadTask(with: url)
            activeDownloads[url] = task
            task.resume()
        }
    }
    
    // Write progress update to IPC for main app to read
    private func writeProgressUpdate(requestId: String, progress: Double, appName: String) {
        let progressDir = "/tmp/patchmaster-ipc/progress"
        try? FileManager.default.createDirectory(atPath: progressDir, withIntermediateDirectories: true)
        
        let progressFile = "\(progressDir)/\(requestId).json"
        let progressData = [
            "requestId": requestId,
            "appName": appName,
            "progress": progress,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: progressData) {
            try? jsonData.write(to: URL(fileURLWithPath: progressFile))
        }
        
        print("📊 \(appName): \(Int(progress * 100))%")
    }
    
    func download(from urlString: String,
                  progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        
        progressHandlers[url] = progress
        completionHandlers[url] = completion
        
        let task = session.downloadTask(with: url)
        activeDownloads[url] = task
        task.resume()
    }
    
    func cancel(urlString: String) {
        guard let url = URL(string: urlString),
              let task = activeDownloads[url] else { return }
        
        task.cancel()
        cleanup(url: url)
    }
    
    private func cleanup(url: URL) {
        activeDownloads.removeValue(forKey: url)
        progressHandlers.removeValue(forKey: url)
        completionHandlers.removeValue(forKey: url)
        requestIds.removeValue(forKey: url)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.originalRequest?.url else { return }
        
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        
        try? FileManager.default.removeItem(at: destURL)
        
        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            completionHandlers[url]?(.success(destURL))
        } catch {
            completionHandlers[url]?(.failure(error))
        }
        
        cleanup(url: url)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let url = downloadTask.originalRequest?.url else { return }
        
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandlers[url]?(progress)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let url = task.originalRequest?.url, let error = error else { return }
        completionHandlers[url]?(.failure(error))
        cleanup(url: url)
    }
}
