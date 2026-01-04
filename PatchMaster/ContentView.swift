//
//  ContentView.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//

import SwiftUI
import Foundation

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
        ZStack {
            // Subtle gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with gradient
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "gearshape.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.3, green: 0.6, blue: 1.0),
                                        Color(red: 0.1, green: 0.5, blue: 0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("PatchMaster")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.1, green: 0.2, blue: 0.4),
                                        Color(red: 0.3, green: 0.4, blue: 0.6)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Spacer()
                        
                        if !viewModel.updates.isEmpty {
                            Text("\(viewModel.updates.count) Updates")
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 1.0, green: 0.3, blue: 0.3),
                                            Color(red: 0.9, green: 0.2, blue: 0.2)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(20)
                        }
                        
                        Button(action: {
                            Task {
                                await viewModel.forceRefresh()
                            }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.2, green: 0.7, blue: 0.4),
                                            Color(red: 0.1, green: 0.6, blue: 0.3)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(8)
                        }
                        .disabled(viewModel.isChecking)
                    }
                    
                    if !viewModel.updates.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search apps...", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.7),
                            Color.white.opacity(0.5)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                
                // Content
                if viewModel.isChecking {
                    Spacer()
                    VStack(spacing: 24) {
                        LoadingAnimationView()
                        
                        VStack(spacing: 8) {
                            Text(viewModel.checkingStatus)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)
                                .id(viewModel.checkingStatus)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                .animation(.easeInOut(duration: 0.3), value: viewModel.checkingStatus)
                            
                            AnimatedDotsView()
                                .padding(.top, 4)
                        }
                    }
                    Spacer()
                } else if viewModel.updates.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.7, blue: 0.4),
                                        Color(red: 0.1, green: 0.6, blue: 0.3)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("All apps are up to date")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(red: 0.1, green: 0.2, blue: 0.4))
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
                                    .opacity(0.3)
                            }
                        }
                    }
                }
                
                if !viewModel.updates.isEmpty {
                    Divider()
                        .opacity(0.3)
                    HStack {
                        Spacer()
                        Text("Last checked: \(viewModel.lastChecked, formatter: timeFormatter)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.3))
                }
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

// Animated loading indicator with pulsing circles
struct LoadingAnimationView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let time = context.date.timeIntervalSince1970
            let outerPhase = sin(time * 2.0) // 2 second cycle
            let middlePhase = sin(time * 2.5 + 0.5) // Slightly faster, offset
            
            ZStack {
                // Outer pulsing circle with gradient
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3),
                                Color(red: 0.1, green: 0.5, blue: 0.9).opacity(0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.0 + CGFloat(outerPhase) * 0.2)
                    .opacity(0.4 + Double(outerPhase) * 0.3)
                
                // Middle pulsing circle with gradient
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.5),
                                Color(red: 0.1, green: 0.5, blue: 0.9).opacity(0.5)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + CGFloat(middlePhase) * 0.1)
                    .opacity(0.6 + Double(middlePhase) * 0.2)
                
                // Inner spinning progress view with gradient
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.3, green: 0.6, blue: 1.0),
                                    Color(red: 0.1, green: 0.5, blue: 0.9)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(time * 100))
                }
            }
        }
    }
}

// Animated dots view
struct AnimatedDotsView: View {
    @State private var dotScales: [CGFloat] = [0.5, 0.5, 0.5]
    @State private var dotOpacities: [Double] = [0.5, 0.5, 0.5]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.6, blue: 1.0),
                                Color(red: 0.1, green: 0.5, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScales[index])
                    .opacity(dotOpacities[index])
            }
        }
        .onAppear {
            // Animate each dot with a delay
            for index in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                    withAnimation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        dotScales[index] = 1.0
                        dotOpacities[index] = 1.0
                    }
                }
            }
        }
    }
}
