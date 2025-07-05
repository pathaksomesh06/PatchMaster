import Foundation
import AppKit

class AppInstaller {
    enum InstallError: Error, LocalizedError {
        case unsupportedFormat
        case mountFailed(String)
        case installFailed(String)
        case noAppFound
        case permissionDenied
        
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Unsupported file format"
            case .mountFailed(let msg): return "Mount failed: \(msg)"
            case .installFailed(let msg): return "Install failed: \(msg)"
            case .noAppFound: return "No app found"
            case .permissionDenied: return "Permission denied - daemon not running as root"
            }
        }
    }
    
    static func install(from fileURL: URL, appName: String) async throws {
        // Verify root privileges
        guard getuid() == 0 else {
            print("❌ NOT RUNNING AS ROOT - UID: \(getuid())")
            throw InstallError.permissionDenied
        }
        
        // Rosetta 2 check for Intel-only apps on Apple Silicon
        #if arch(arm64)
        if isIntelOnlyApp(appName: appName) && !isRosettaInstalled() {
            print("❌ Rosetta 2 is required for \(appName) but is not installed. Please run: softwareupdate --install-rosetta --agree-to-license")
            throw InstallError.installFailed("Rosetta 2 is required for Intel-only apps on Apple Silicon.")
        }
        #endif
        
        print("🔧 ROOT INSTALL: \(appName) (UID: \(getuid()))")
        
        let ext = fileURL.pathExtension.lowercased()
        
        switch ext {
        case "dmg":
            try await installDMG(fileURL, appName: appName)
        case "pkg":
            try await installPKG(fileURL)
        default:
            throw InstallError.unsupportedFormat
        }
        
        // Post-install system refresh
        await refreshSystemDatabase()
        
        // Wait for system registration
        try await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
        print("🔄 System refresh complete")

        // User-facing warning for Intel-only apps on Apple Silicon
        #if arch(arm64)
        if isIntelOnlyApp(appName: appName) {
            print("⚠️ Note: \(appName) is Intel-only. If it fails to launch or shows an architecture error, it may not be fully compatible with Apple Silicon, even with Rosetta 2.")
        }
        #endif
    }
    
    private static func installDMG(_ dmgURL: URL, appName: String) async throws {
        print("📦 ROOT DMG INSTALL: \(dmgURL.path)")
        
        // Force kill all processes
        await forceKillProcesses(appName: appName)
        
        // Mount with explicit permissions
        let mountPoint = try await mountDMGAsRoot(dmgURL)
        defer {
            Task { await unmountDMGAsRoot(mountPoint) }
        }
        
        // Find app or pkg in DMG
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint) else {
            throw InstallError.noAppFound
        }
        print("📁 DMG CONTENTS: \(contents)")
        
        // Try to find .app bundle
        if let appPath = contents.first(where: { $0.hasSuffix(".app") && !$0.lowercased().contains("install") && !$0.lowercased().contains("uninstall") }) {
            try await forceInstallApp(from: "\(mountPoint)/\(appPath)", appName: appName)
            return
        }
        // Try to find .pkg installer
        if let pkgPath = contents.first(where: { $0.hasSuffix(".pkg") }) {
            print("📦 Found .pkg in DMG: \(pkgPath)")
            try await installPKG(URL(fileURLWithPath: "\(mountPoint)/\(pkgPath)"))
            return
        }
        throw InstallError.noAppFound
    }
    
    private static func mountDMGAsRoot(_ dmgURL: URL) async throws -> String {
        let mountPoint = "/tmp/pm_root_\(UUID().uuidString.prefix(8))"
        
        // Create mount point with root permissions
        let mkdir = Process()
        mkdir.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        mkdir.arguments = ["-p", mountPoint]
        try mkdir.run()
        mkdir.waitUntilExit()
        
        // Mount as root
        let hdiutil = Process()
        hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint, "-nobrowse", "-readonly", "-quiet", "-noautoopen"]
        
        let pipe = Pipe()
        hdiutil.standardOutput = pipe
        hdiutil.standardError = pipe
        
        try hdiutil.run()
        hdiutil.waitUntilExit()
        
        if hdiutil.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("❌ MOUNT FAILED: \(output)")
            throw InstallError.mountFailed("hdiutil exit: \(hdiutil.terminationStatus)")
        }
        
        print("✅ MOUNTED: \(mountPoint)")
        return mountPoint
    }
    
    private static func unmountDMGAsRoot(_ mountPoint: String) async {
        let hdiutil = Process()
        hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["detach", mountPoint, "-quiet", "-force"]
        try? hdiutil.run()
        hdiutil.waitUntilExit()
        
        // Force cleanup
        let rm = Process()
        rm.executableURL = URL(fileURLWithPath: "/bin/rm")
        rm.arguments = ["-rf", mountPoint]
        try? rm.run()
        rm.waitUntilExit()
    }
    
    private static func findAppInDMG(mountPoint: String, appName: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mountPoint) else {
            return nil
        }
        
        print("📁 DMG CONTENTS: \(contents)")
        
        // Find .app bundle
        for item in contents {
            if item.hasSuffix(".app") && !item.lowercased().contains("install") && !item.lowercased().contains("uninstall") {
                return "\(mountPoint)/\(item)"
            }
        }
        
        return nil
    }
    
    private static func forceInstallApp(from sourcePath: String, appName: String) async throws {
        let appName = URL(fileURLWithPath: sourcePath).lastPathComponent
        let destPath = "/Applications/\(appName)"
        
        print("📋 FORCE INSTALL: \(sourcePath) → \(destPath)")
        
        // Force remove existing (even if running)
        if FileManager.default.fileExists(atPath: destPath) {
            print("🗑️ FORCE REMOVE EXISTING")
            let rm = Process()
            rm.executableURL = URL(fileURLWithPath: "/bin/rm")
            rm.arguments = ["-rf", destPath]
            try rm.run()
            rm.waitUntilExit()
            
            if rm.terminationStatus != 0 {
                print("⚠️ REMOVE FAILED, CONTINUING...")
            }
        }
        
        // Force copy
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = ["-R", sourcePath, destPath]
        
        let pipe = Pipe()
        cp.standardOutput = pipe
        cp.standardError = pipe
        
        try cp.run()
        cp.waitUntilExit()
        
        if cp.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("❌ COPY FAILED: \(output)")
            throw InstallError.installFailed("Copy failed: \(output)")
        }
        
        // Force fix permissions
        await forceFixPermissions(destPath)
        
        print("✅ FORCE INSTALL COMPLETE")
    }
    
    private static func forceFixPermissions(_ appPath: String) async {
        let commands = [
            ["/usr/sbin/chown", "-R", "root:admin", appPath],
            ["/bin/chmod", "-R", "755", appPath],
            ["/usr/bin/xattr", "-dr", "com.apple.quarantine", appPath]
        ]
        
        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            try? process.run()
            process.waitUntilExit()
        }
        
        print("🔧 Permissions fixed")
    }
    
    private static func forceKillProcesses(appName: String) async {
        let processNames = [
            appName.replacingOccurrences(of: ".app", with: ""),
            appName.replacingOccurrences(of: " ", with: ""),
            "Android Studio",
            "AndroidStudio"
        ]
        
        print("🔄 Killing processes: \(processNames)")
        
        for name in processNames {
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-9", "-f", name]
            try? pkill.run()
            pkill.waitUntilExit()
            
            let pkill2 = Process()
            pkill2.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill2.arguments = ["-9", name]
            try? pkill2.run()
            pkill2.waitUntilExit()
        }
        
        // Wait for processes to die
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
    }
    
    private static func installPKG(_ pkgURL: URL) async throws {
        print("📦 ROOT PKG INSTALL: \(pkgURL.path)")
        
        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        installer.arguments = ["-pkg", pkgURL.path, "-target", "/"]
        
        let pipe = Pipe()
        installer.standardOutput = pipe
        installer.standardError = pipe
        
        try installer.run()
        installer.waitUntilExit()
        
        if installer.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw InstallError.installFailed("PKG failed: \(output)")
        }
        
        print("✅ ROOT PKG COMPLETE")
    }
    
    private static func refreshSystemDatabase() async {
        print("🔄 Refreshing system database...")
        
        let commands = [
                    // Kill Launch Services database
                    ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
                    // Rebuild Launch Services database
                    ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
                    // Touch Applications folder to force filesystem update
                    ["/usr/bin/touch", "/Applications"]
                ]
        
        for command in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try? process.run()
            process.waitUntilExit()
            
            // Small delay between commands
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        print("🔄 Database refresh complete")
    }
    
    // Detect if app is Intel-only (manual list for now)
    private static func isIntelOnlyApp(appName: String) -> Bool {
        let intelOnlyApps = ["Jabra Direct"]
        return intelOnlyApps.contains(where: { appName.localizedCaseInsensitiveContains($0) })
    }
    
    // Check if Rosetta 2 is installed
    private static func isRosettaInstalled() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }
}
