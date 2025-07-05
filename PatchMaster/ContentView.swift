//
//  ContentView.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import SwiftUI

extension String {
    func versionWithLineBreakBeforeParenthesis() -> String {
        return self.replacingOccurrences(of: #" ?\("#, with: "\n(", options: .regularExpression)
    }
}

extension MockAppUpdate {
    var uniqueID: String { installedBundleId }
}

struct ContentView: View {
    @StateObject private var viewModel = UpdateViewModel()
    @State private var searchText = ""
    
    var filteredUpdates: [MockAppUpdate] {
        if searchText.isEmpty {
            return viewModel.updates
        } else {
            return viewModel.updates.filter {
                $0.appName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue.gradient)
                    Text("PatchMaster")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                    Spacer()
                    
                    if !viewModel.updates.isEmpty {
                        Text("\(viewModel.updates.count) Updates Available")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(20)
                    }
                    
                    Button(action: {
                        Task {
                            await viewModel.forceRefresh()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isChecking)
                }
                
                if !viewModel.updates.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search apps...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content
            if viewModel.isChecking {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                    Text("Checking for updates...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.updates.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green.gradient)
                    Text("All apps are up to date")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Your system is running the latest versions")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredUpdates, id: \.uniqueID) { update in
                            UpdateRowPro(
                                update: update,
                                onComplete: {
                                    Task {
                                        await viewModel.refreshAfterInstall()
                                    }
                                }
                            )
                            Divider()
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            
            if !viewModel.updates.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Text("Last checked: \(viewModel.lastChecked, formatter: timeFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.controlBackgroundColor))
        .task {
            await viewModel.checkForUpdates()
        }
    }
    
    var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }
    
    private func updateAllApps() async {
        for update in viewModel.updates {
            // Trigger update for each app
            // Implementation would go here
        }
        await viewModel.refreshAfterInstall()
    }
}

struct UpdateRowPro: View {
    let update: MockAppUpdate
    let onComplete: () -> Void
    
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var isInstalling = false
    @State private var isHovering = false
    @State private var errorMessage: String?
    @State private var showRetryOption = false
    @State private var retryCount = 0
    @State private var isCompleted = false
    
    var body: some View {
        HStack(spacing: 16) {
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)
                
                if let icon = update.installedAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(update.appName.prefix(2).uppercased())
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
            
            // App Info
            VStack(alignment: .leading, spacing: 6) {
                Text(update.appName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            if update.currentVersion.contains("(") {
                                let components = update.currentVersion.components(separatedBy: " (")
                                Text("Current: \(components[0])")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if components.count > 1 {
                                    let buildNumber = components[1].replacingOccurrences(of: ")", with: "")
                                    Text("(\(buildNumber))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Current: \(update.currentVersion)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.green)
                        Text("Available: \(update.newVersion)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                if isDownloading {
                    VStack(spacing: 4) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 200)
                        
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if isCompleted {
                    Text("✅ Update completed successfully")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Action Button
            updateButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(isHovering ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    @ViewBuilder
    var updateButton: some View {
        if isCompleted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Updated")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }
            .frame(width: 120)
        } else if isInstalling {
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                Text("Installing...")
                    .font(.system(size: 13))
            }
            .frame(width: 120)
        } else if isDownloading {
            Button(action: cancelDownload) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Cancel")
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .frame(width: 120)
        } else {
            Button(action: performUpdate) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Update")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .frame(width: 120)
        }
    }
    
    private func performUpdate() {
        isDownloading = true
        errorMessage = nil
        showRetryOption = false
        isCompleted = false
        
        Task {
            let result: DaemonResponse
            if update.source == "native" {
                isInstalling = true
                downloadProgress = 0.8
                result = await DaemonCommunicator.shared.installNativeAppWithResult(
                    bundleId: update.installedBundleId,
                    appName: update.appName
                )
            } else {
                result = await DaemonCommunicator.shared.downloadAndInstallAppWithResult(
                    from: update.downloadURL ?? "",
                    appName: update.appName
                ) { progress in
                    DispatchQueue.main.async {
                        self.downloadProgress = progress
                    }
                }
            }
            await MainActor.run {
                isDownloading = false
                isInstalling = false
                if result.success {
                    isCompleted = true
                    errorMessage = nil
                    onComplete()
                } else {
                    isCompleted = false
                    errorMessage = result.error ?? "Unknown error"
                    showRetryOption = true
                }
            }
        }
    }
    
    private func getUserFriendlyErrorMessage(error: Error, appName: String) -> (message: String, canRetry: Bool) {
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("timeout") || errorDescription.contains("request timeout") {
            if appName.lowercased().contains("microsoft") || appName.lowercased().contains("office") {
                return ("Microsoft \(appName) is a large download that may take 10+ minutes. Please check your internet connection and try again.", true)
            } else {
                return ("\(appName) download timed out. This may be a large file - please check your internet connection and try again.", true)
            }
        }
        
        if errorDescription.contains("network") || errorDescription.contains("connection") || errorDescription.contains("internet") {
            return ("Network connection issue. Please check your internet connection and try again.", true)
        }
        
        if errorDescription.contains("authorization") || errorDescription.contains("permission") || errorDescription.contains("admin") {
            return ("Administrator permission required. Please ensure you have admin rights and try again.", true)
        }
        
        if appName.lowercased().contains("microsoft") && errorDescription.contains("not found") {
            return ("Microsoft \(appName) may not be available in the current catalog. Try updating from Microsoft directly or check Microsoft AutoUpdate.", false)
        }
        
        if errorDescription.contains("install") || errorDescription.contains("copy") {
            return ("Installation failed. Please ensure \(appName) is not currently running and try again.", true)
        }
        
        if errorDescription.contains("space") || errorDescription.contains("disk") {
            return ("Insufficient disk space. Please free up some space and try again.", true)
        }
        
        if retryCount < 2 {
            return ("Update failed: \(error.localizedDescription). Click retry to try again.", true)
        } else {
            return ("Update failed after multiple attempts: \(error.localizedDescription). Please try updating \(appName) manually.", false)
        }
    }
    
    private func retryUpdate() {
        retryCount += 1
        performUpdate()
    }
    
    private func cancelDownload() {
        if let downloadURL = update.downloadURL {
            Task {
                do {
                    try await DaemonCommunicator.shared.cancelDownload(downloadURL: downloadURL)
                    await MainActor.run {
                        isDownloading = false
                        downloadProgress = 0
                        errorMessage = nil
                    }
                } catch {
                    await MainActor.run {
                        isDownloading = false
                        downloadProgress = 0
                        errorMessage = "Failed to cancel download: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            isDownloading = false
            downloadProgress = 0
        }
    }
}
