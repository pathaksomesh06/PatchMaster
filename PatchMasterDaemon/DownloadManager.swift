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
    private var activeDownloads: [URLSessionDownloadTask: URL] = [:] // Map task to URL for handler lookup
    private var progressHandlers: [URL: (Double) -> Void] = [:]
    private var completionHandlers: [URL: (Result<URL, Error>) -> Void] = [:]
    private var requestIds: [URL: String] = [:]
    
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    
    // Enhanced download method for daemon use with progress tracking via IPC
    func downloadWithProgress(from urlString: String, appName: String, requestId: String) async throws -> DownloadResult {
        guard let _ = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL: \(urlString)"])
        }
        
        print("📥 Starting download for \(appName) from \(urlString)")
        
        // Check if this is an XML feed and extract the actual download URL
        let actualDownloadURL = try await extractActualDownloadURL(from: urlString, appName: appName)
        
        return try await withCheckedThrowingContinuation { continuation in
            // IMPORTANT: Store handlers with actualDownloadURL as key, since that's what the delegate receives
            // Store request ID for progress updates
            requestIds[actualDownloadURL] = requestId
            
            // Set up progress handler to write to IPC
            progressHandlers[actualDownloadURL] = { progress in
                self.writeProgressUpdate(requestId: requestId, progress: progress, appName: appName)
            }
            
            // Set up completion handler
            completionHandlers[actualDownloadURL] = { result in
                switch result {
                case .success(let tempURL):
                    // Detect file extension more reliably
                    var fileExtension = "dmg" // default
                    let urlExtension = actualDownloadURL.pathExtension.lowercased()
                    
                    print("🔍 Download URL: \(actualDownloadURL)")
                    print("🔍 URL Extension: \(urlExtension)")
                    
                    // GitHub Desktop often uses .zip
                    if urlExtension == "zip" || actualDownloadURL.absoluteString.contains("github.com") && actualDownloadURL.absoluteString.contains(".zip") {
                        fileExtension = "zip"
                    } else if urlExtension == "pkg" {
                        fileExtension = "pkg"
                    } else if !urlExtension.isEmpty {
                        fileExtension = urlExtension
                    }
                    
                    print("🔍 Detected file extension: \(fileExtension)")
                    
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
            
            let task = session.downloadTask(with: actualDownloadURL)
            activeDownloads[task] = actualDownloadURL  // Store URL for delegate lookup
            task.resume()
        }
    }
    
    // Extract actual download URL from XML feeds
    private func extractActualDownloadURL(from urlString: String, appName: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"])
        }
        
        // If it's not an XML feed, return the original URL
        if !urlString.lowercased().contains(".xml") {
            return url
        }
        
        print("🔍 Detected XML feed, extracting actual download URL...")
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let xmlString = String(data: data, encoding: .utf8) ?? ""
            
            // Try to extract download URL from various XML feed formats
            if let downloadURL = extractDownloadURLFromXML(xmlString, appName: appName) {
                print("✅ Extracted download URL from XML: \(downloadURL)")
                return downloadURL
            } else {
                print("⚠️ Could not extract download URL from XML, using original URL")
                return url
            }
        } catch {
            print("⚠️ Failed to parse XML feed, using original URL: \(error)")
            return url
        }
    }
    
    // Extract download URL from XML content
    private func extractDownloadURLFromXML(_ xmlString: String, appName: String) -> URL? {
        // Common patterns for download URLs in XML feeds
        let patterns = [
            // Sparkle RSS feed patterns (most common for macOS apps)
            "enclosure[^>]*url=[\"']([^\"']*\\.(dmg|pkg|zip))[\"']",
            "enclosure[^>]*url=[\"']([^\"']+)[\"']",
            // RSS/Atom feed patterns
            "link.*href=[\"']([^\"']+)[\"']",
            // Generic download patterns
            "download.*url=[\"']([^\"']+)[\"']",
            "url=[\"']([^\"']+)[\"']",
            // Direct file links
            "href=[\"']([^\"']*\\.(dmg|pkg|zip))[\"']",
            "url=[\"']([^\"']*\\.(dmg|pkg|zip))[\"']"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString)) {
                
                let matchRange = match.range(at: 1)
                if let range = Range(matchRange, in: xmlString) {
                    let extractedURL = String(xmlString[range])
                    if let url = URL(string: extractedURL) {
                        // Validate that it's a downloadable file
                        if ["dmg", "pkg", "zip"].contains(url.pathExtension.lowercased()) {
                            return url
                        }
                    }
                }
            }
        }
        
        return nil
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
        activeDownloads[task] = url  // Store URL for delegate lookup
        task.resume()
    }
    
    func cancel(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        // Find the task with this URL
        if let task = activeDownloads.first(where: { $0.value == url })?.key {
            task.cancel()
            cleanup(url: url)
        }
    }
    
    private func cleanup(url: URL) {
        // Remove the task entry for this URL
        activeDownloads.keys.forEach { task in
            if activeDownloads[task] == url {
                activeDownloads.removeValue(forKey: task)
            }
        }
        progressHandlers.removeValue(forKey: url)
        completionHandlers.removeValue(forKey: url)
        requestIds.removeValue(forKey: url)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Look up the URL we stored for this task
        guard let url = activeDownloads[downloadTask] else {
            print("❌ NO URL FOUND for download task! activeDownloads has \(activeDownloads.count) entries")
            print("❌ Task: \(downloadTask)")
            print("❌ URL from original request: \(downloadTask.originalRequest?.url?.absoluteString ?? "NIL")")
            return
        }
        
        print("✅ Found URL in activeDownloads: \(url.absoluteString)")
        print("📥 Download completed!")
        
        // Create a temporary filename - use UUID to ensure it's unique
        let tempFileName = UUID().uuidString
        var destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(tempFileName)
        
        // Try to detect file type from the downloaded file
        if let fileType = detectFileType(at: location) {
            destURL = destURL.appendingPathExtension(fileType)
            print("✅ Detected file type: \(fileType)")
        } else {
            // Fallback: try to extract from URL path
            let urlExt = url.pathExtension.lowercased()
            if !urlExt.isEmpty && ["dmg", "pkg", "zip"].contains(urlExt) {
                destURL = destURL.appendingPathExtension(urlExt)
                print("✅ Using URL extension: \(urlExt)")
            } else {
                // Default to dmg
                destURL = destURL.appendingPathExtension("dmg")
                print("⚠️ Defaulting to dmg")
            }
        }
        
        print("📥 Moving to: \(destURL.path)")
        
        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            print("✅ File moved successfully to \(destURL.path)")
            
            print("🔍 Looking for completion handler... completionHandlers has \(completionHandlers.count) entries")
            print("🔍 Handler URL: \(url.absoluteString)")
            
            if let handler = completionHandlers[url] {
                print("✅ FOUND completion handler! Calling it now...")
                handler(.success(destURL))
                print("✅ Handler called successfully")
            } else {
                print("❌ NO COMPLETION HANDLER FOUND!")
                print("❌ Available keys: \(completionHandlers.keys.map { $0.absoluteString })")
            }
        } catch {
            print("❌ Move failed: \(error)")
            completionHandlers[url]?(.failure(error))
        }
        
        cleanup(url: url)
    }
    
    private func detectFileType(at url: URL) -> String? {
        // Read first few bytes to detect file type
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let data = handle.readData(ofLength: 8)
        handle.closeFile()
        
        // Check magic bytes
        let bytes = [UInt8](data)
        
        // ZIP: PK (0x504B)
        if bytes.count >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B {
            return "zip"
        }
        
        // DMG: various signatures, but often starts with 0x78
        if bytes.count >= 1 && bytes[0] == 0x78 {
            return "dmg"
        }
        
        // PKG: xar archive (0x78617221)
        if bytes.count >= 4 && bytes[0] == 0x78 && bytes[1] == 0x61 && bytes[2] == 0x72 && bytes[3] == 0x21 {
            return "pkg"
        }
        
        return nil
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let url = activeDownloads[downloadTask] else { return }
        
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandlers[url]?(progress)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let url = activeDownloads[downloadTask],
              let error = error else { return }
        completionHandlers[url]?(.failure(error))
        cleanup(url: url)
    }
}
