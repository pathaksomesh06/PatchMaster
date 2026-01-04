//
//  UpdateViewModel.swift
//  IntunePatcher
//
//  Created by Somesh Pathak on 02/07/2025.
//


import Foundation

@MainActor
class UpdateViewModel: ObservableObject {
    @Published var updates: [MockAppUpdate] = []
    @Published var isChecking = false
    @Published var checkingStatus = "Checking for updates..."
    @Published var lastChecked = Date()
    
    func checkForUpdates() async {
        isChecking = true
        defer {
            isChecking = false
            lastChecked = Date()
        }
        
        do {
            checkingStatus = "Scanning installed apps..."
            updates = try await DaemonCommunicator.shared.checkForUpdates() { status in
                self.checkingStatus = status
            }
        } catch {
            print("Error checking updates: \(error)")
        }
    }
    
    func refreshAfterInstall() async {
        // Wait longer for system to fully register the new app
        try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
        
        print("🔄 Refreshing app list after installation...")
        
        // Force refresh
        await checkForUpdates()
        
        print("✅ Post-install refresh complete")
    }
    
    func forceRefresh() async {
        print("🔄 Force refreshing app list...")
        await checkForUpdates()
    }
}
