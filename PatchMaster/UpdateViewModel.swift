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
    @Published var lastChecked = Date()
    
    func checkForUpdates() async {
        isChecking = true
        defer {
            isChecking = false
            lastChecked = Date()
        }
        
        do {
            updates = try await DaemonCommunicator.shared.checkForUpdates()
        } catch {
            print("Error checking updates: \(error)")
        }
    }
    
    func refreshAfterInstall() async {
        // Wait for installation to complete and system to register
        try? await Task.sleep(nanoseconds: 12_000_000_000) // 12 seconds
        
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
