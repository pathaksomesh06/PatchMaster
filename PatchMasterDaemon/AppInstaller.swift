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
        print("📦 Installing \(appName) from \(fileURL.path)")
        print("📦 File extension: '\(ext)'")
        
        // If no extension, try to detect file type
        var actualExt = ext
        if ext.isEmpty {
            print("⚠️ No file extension detected, checking file type...")
            if let detectedType = detectFileType(at: fileURL) {
                actualExt = detectedType
                print("✅ Detected file type: \(detectedType)")
            }
        }
        
        switch actualExt {
        case "dmg":
            try await installDMG(fileURL, appName: appName)
        case "pkg":
            try await installPKG(fileURL)
        case "zip":
            try await installZIP(fileURL, appName: appName)
        default:
            print("❌ Unsupported format: '\(actualExt)'")
            throw InstallError.unsupportedFormat
        }
        
        // Post-install system refresh
        await refreshSystemDatabase()
        
        // Extra aggressive refresh for specific apps
        if appName.contains("GitHub") || appName.contains("PowerShell") {
            print("🔄 Extra refresh for \(appName)...")
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            await refreshSystemDatabase()
        }
        
        // Some installers (e.g., Zoom) auto-launch post-install; ensure they are terminated
        await suppressAutoLaunch(appName: appName)
        
        // Wait for system registration
        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
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
        let mountPoint: String
        do {
            mountPoint = try await mountDMGAsRoot(dmgURL)
        } catch {
            print("❌ DMG MOUNT ERROR: \(error)")
            throw InstallError.mountFailed("Failed to mount DMG: \(error.localizedDescription)")
        }
        
        defer {
            Task { await unmountDMGAsRoot(mountPoint) }
        }
        
        // Find app or pkg in DMG
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint) else {
            print("❌ Cannot read mount point contents: \(mountPoint)")
            throw InstallError.noAppFound
        }
        print("📁 DMG CONTENTS: \(contents)")
        
        // Try to find .app bundle
        if let appPath = contents.first(where: { $0.hasSuffix(".app") && !$0.lowercased().contains("install") && !$0.lowercased().contains("uninstall") }) {
            print("📱 Found .app in DMG: \(appPath)")
            try await forceInstallApp(from: "\(mountPoint)/\(appPath)", appName: appName)
            return
        }
        
        // Try to find .pkg installer
        if let pkgPath = contents.first(where: { $0.hasSuffix(".pkg") }) {
            print("📦 Found .pkg in DMG: \(pkgPath)")
            try await installPKG(URL(fileURLWithPath: "\(mountPoint)/\(pkgPath)"))
            return
        }
        
        print("❌ No .app or .pkg found in DMG contents: \(contents)")
        throw InstallError.noAppFound
    }
    
    private static func mountDMGAsRoot(_ dmgURL: URL) async throws -> String {
        let mountPoint = "/tmp/pm_root_\(UUID().uuidString.prefix(8))"
        
        print("🔧 MOUNTING DMG: \(dmgURL.path)")
        print("📁 Mount point: \(mountPoint)")
        
        // Verify DMG file exists and is readable
        guard FileManager.default.fileExists(atPath: dmgURL.path) else {
            throw InstallError.mountFailed("DMG file does not exist: \(dmgURL.path)")
        }
        
        // Check file permissions
        let attributes = try FileManager.default.attributesOfItem(atPath: dmgURL.path)
        print("📄 DMG file size: \(attributes[.size] ?? "unknown") bytes")
        
        // Create mount point with root permissions
        let mkdir = Process()
        mkdir.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        mkdir.arguments = ["-p", mountPoint]
        try mkdir.run()
        mkdir.waitUntilExit()
        
        if mkdir.terminationStatus != 0 {
            throw InstallError.mountFailed("Failed to create mount point: \(mountPoint)")
        }
        
        // Set proper permissions on mount point
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["755", mountPoint]
        try chmod.run()
        chmod.waitUntilExit()
        
        // Mount as root with verbose output for debugging
        let hdiutil = Process()
        hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint, "-nobrowse", "-readonly", "-quiet", "-noautoopen"]
        
        let pipe = Pipe()
        hdiutil.standardOutput = pipe
        hdiutil.standardError = pipe
        
        print("🚀 Running hdiutil attach...")
        try hdiutil.run()
        hdiutil.waitUntilExit()
        
        if hdiutil.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("❌ MOUNT FAILED: \(output)")
            print("❌ Exit code: \(hdiutil.terminationStatus)")
            
            // Try alternative mount method
            print("🔄 Trying alternative mount method...")
            return try await mountDMGAlternative(dmgURL, mountPoint: mountPoint)
        }
        
        // Verify mount point is accessible
        guard FileManager.default.fileExists(atPath: mountPoint) else {
            throw InstallError.mountFailed("Mount point not accessible after mount")
        }
        
        print("✅ MOUNTED: \(mountPoint)")
        return mountPoint
    }
    
    private static func mountDMGAlternative(_ dmgURL: URL, mountPoint: String) async throws -> String {
        print("🔄 Alternative mount method...")
        
        // Try without readonly flag
        let hdiutil = Process()
        hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["attach", dmgURL.path, "-mountpoint", mountPoint, "-nobrowse", "-noautoopen"]
        
        let pipe = Pipe()
        hdiutil.standardOutput = pipe
        hdiutil.standardError = pipe
        
        try hdiutil.run()
        hdiutil.waitUntilExit()
        
        if hdiutil.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("❌ ALTERNATIVE MOUNT FAILED: \(output)")
            throw InstallError.mountFailed("Alternative mount failed: \(output)")
        }
        
        print("✅ ALTERNATIVE MOUNT SUCCESS: \(mountPoint)")
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
        // Debug: Log what we're being asked to kill
        print("🔍 forceKillProcesses called with appName: '\(appName)'")
        
        // Critical system processes that should NEVER be killed (case-insensitive)
        let protectedProcesses = Set([
            "dock", "finder", "windowserver", "loginwindow", "kernel_task",
            "launchd", "systemuiserver", "notificationcenter", "spotlight",
            "mds", "mds_stores", "mdworker", "cfprefsd", "distnoted",
            "usereventagent", "sharingd", "airplayuiagent", "controlcenter",
            "patchmaster", "patchmasterdaemon", // Don't kill ourselves!
            "xcode", "xcodebuild", "swift", "swiftc" // Don't kill build tools
        ])
        
        // Clean the app name - remove .app extension and get the executable name
        var cleanName = appName.replacingOccurrences(of: ".app", with: "")
        cleanName = cleanName.replacingOccurrences(of: " ", with: "")
        let cleanNameLower = cleanName.lowercased()
        let appNameLower = appName.lowercased()
        
        // Skip if it's a protected process (case-insensitive check)
        guard !protectedProcesses.contains(cleanNameLower) && 
              !protectedProcesses.contains(appNameLower) &&
              cleanName.count > 2 else { // Also skip very short names that could match anything
            print("⚠️ Skipping kill for protected/generic process: \(appName) (cleaned: \(cleanName))")
            return
        }
        
        // Additional safety: Don't kill if the name is too generic or could match system processes
        let genericNames = ["system", "core", "daemon", "agent", "server", "helper", "tool"]
        if genericNames.contains(where: { cleanNameLower.contains($0) && cleanName.count < 10 }) {
            print("⚠️ Skipping kill for potentially generic process name: \(appName)")
            return
        }
        
        // Only try to kill processes with the exact executable name (not full command line)
        // This is much safer than -f flag which matches entire command line
        print("🔄 Attempting to kill processes for: \(cleanName) (original: \(appName))")
        
        // First, check if the process actually exists using pgrep (safer than killall)
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", cleanName] // -x for exact match only
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = pipe
        try? pgrep.run()
        pgrep.waitUntilExit()
        
        // Only kill if the process actually exists
        if pgrep.terminationStatus == 0 {
            // Process exists, safe to kill
            let killall = Process()
            killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killall.arguments = ["-9", cleanName]
            try? killall.run()
            killall.waitUntilExit()
            
            if killall.terminationStatus == 0 {
                print("✅ Successfully killed process: \(cleanName)")
            } else {
                print("⚠️ killall returned exit code: \(killall.terminationStatus)")
            }
        } else {
            print("ℹ️ Process \(cleanName) not found, skipping kill")
        }
        
        // Wait for processes to die
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    }

    private static func suppressAutoLaunch(appName: String) async {
        // Kill common auto-launchers right after install to prevent unwanted UI popups
        // Only target specific known auto-launchers, not the app being installed
        let autoLauncherNames = ["zoom.us", "Zoom"] // Only known problematic auto-launchers
        
        print("🔇 Suppressing auto-launch for known auto-launchers: \(autoLauncherNames)")
        for name in autoLauncherNames {
            // Use killall which is safer - only matches process names
            let killall = Process()
            killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killall.arguments = ["-9", name]
            try? killall.run()
            killall.waitUntilExit()
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // small pause after kill
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
        
        // NOTE: We intentionally do NOT use lsregister -kill as it causes Dock to restart
        // Instead, we just register the apps and touch the Applications folder
        let commands = [
                    // Register apps in Launch Services database (without killing it)
                    ["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", "-R", "/Applications"],
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
    
    // Detect file type by magic bytes
    private static func detectFileType(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let data = handle.readData(ofLength: 8)
        handle.closeFile()
        
        let bytes = [UInt8](data)
        
        // ZIP: PK (0x504B)
        if bytes.count >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B {
            return "zip"
        }
        
        // DMG: various signatures
        if bytes.count >= 1 && bytes[0] == 0x78 {
            return "dmg"
        }
        
        // PKG: xar archive
        if bytes.count >= 4 && bytes[0] == 0x78 && bytes[1] == 0x61 && bytes[2] == 0x72 && bytes[3] == 0x21 {
            return "pkg"
        }
        
        return nil
    }
    
    private static func installZIP(_ zipURL: URL, appName: String) async throws {
        print("📦 ROOT ZIP INSTALL: \(zipURL.path)")
        
        // Force kill processes
        await forceKillProcesses(appName: appName)
        
        // Create temp extraction directory
        let extractDir = "/tmp/pm_zip_\(UUID().uuidString.prefix(8))"
        let mkdir = Process()
        mkdir.executableURL = URL(fileURLWithPath: "/bin/mkdir")
        mkdir.arguments = ["-p", extractDir]
        try mkdir.run()
        mkdir.waitUntilExit()
        
        // Extract ZIP
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zipURL.path, "-d", extractDir]
        
        let pipe = Pipe()
        unzip.standardOutput = pipe
        unzip.standardError = pipe
        
        try unzip.run()
        unzip.waitUntilExit()
        
        if unzip.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw InstallError.installFailed("Unzip failed: \(output)")
        }
        
        // Find .app in extracted contents
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: extractDir) else {
            throw InstallError.noAppFound
        }
        
        print("📁 ZIP CONTENTS: \(contents)")
        
        // Find the .app bundle
        var appPath: String? = nil
        for item in contents {
            if item.hasSuffix(".app") {
                appPath = "\(extractDir)/\(item)"
                break
            }
            // Check subdirectories
            let itemPath = "\(extractDir)/\(item)"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                if let subContents = try? fm.contentsOfDirectory(atPath: itemPath) {
                    for subItem in subContents where subItem.hasSuffix(".app") {
                        appPath = "\(itemPath)/\(subItem)"
                        break
                    }
                }
            }
            if appPath != nil { break }
        }
        
        guard let foundAppPath = appPath else {
            throw InstallError.noAppFound
        }
        
        // Install the app
        try await forceInstallApp(from: foundAppPath, appName: appName)
        
        // Cleanup
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/rm")
        cleanup.arguments = ["-rf", extractDir]
        try? cleanup.run()
        cleanup.waitUntilExit()
        
        print("✅ ZIP INSTALL COMPLETE")
    }
}
