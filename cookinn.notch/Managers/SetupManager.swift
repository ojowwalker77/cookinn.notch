import Foundation
import SwiftUI
import AppKit
import Combine

enum SetupStatus: Equatable {
    case unknown          // Haven't checked yet
    case notInstalled     // Hooks not found
    case installed        // Fully configured
    case needsUpdate      // Hooks exist but settings.json missing entries
    case installing       // Currently installing
}

enum InstallError: LocalizedError {
    case hooksNotFoundInBundle
    case failedToCreateDirectory(Error)
    case failedToCopyHooks(Error)
    case failedToUpdateSettings(Error)
    case invalidSettingsJson

    var errorDescription: String? {
        switch self {
        case .hooksNotFoundInBundle:
            return "Hook scripts not found in app bundle"
        case .failedToCreateDirectory(let error):
            return "Failed to create config directory: \(error.localizedDescription)"
        case .failedToCopyHooks(let error):
            return "Failed to copy hook scripts: \(error.localizedDescription)"
        case .failedToUpdateSettings(let error):
            return "Failed to update Claude settings: \(error.localizedDescription)"
        case .invalidSettingsJson:
            return "Existing settings.json is not valid JSON"
        }
    }
}

@MainActor
final class SetupManager: ObservableObject {
    static let shared = SetupManager()

    @Published var setupStatus: SetupStatus = .unknown
    @Published var isChecking: Bool = false
    @Published var isInstalling: Bool = false
    @Published var installError: String?

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cookinn-notch")
    private let hookScript = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cookinn-notch/notch-hook.sh")
    private let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    private let claudeSettings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    // Hook types to register in settings.json
    private let hookTypes = [
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SubagentStop",
        "Notification",
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit"
    ]

    private init() {}

    func checkSetup() async -> SetupStatus {
        isChecking = true
        defer { isChecking = false }

        let fm = FileManager.default

        // Check if hook script exists
        guard fm.fileExists(atPath: hookScript.path) else {
            setupStatus = .notInstalled
            return .notInstalled
        }

        // Check if settings.json has our hooks configured
        if checkSettingsJson() {
            setupStatus = .installed
            return .installed
        } else {
            setupStatus = .needsUpdate
            return .needsUpdate
        }
    }

    func getInstallCommand() -> String {
        let possiblePaths = [
            "/Applications/cookinn.notch.app",
            Bundle.main.bundlePath
        ]

        for path in possiblePaths {
            let scriptPath = "\(path)/Contents/Resources/hooks/install.sh"
            if FileManager.default.fileExists(atPath: scriptPath) {
                return scriptPath
            }
        }

        // Fallback
        return "/Applications/cookinn.notch.app/Contents/Resources/hooks/install.sh"
    }

    func copyCommandToClipboard() {
        let command = getInstallCommand()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    func refreshStatus() async {
        _ = await checkSetup()
    }

    // MARK: - Auto Install

    /// Installs hooks automatically without requiring Terminal
    /// Returns true on success, false on failure (check installError for details)
    func installHooks() async -> Bool {
        isInstalling = true
        installError = nil
        setupStatus = .installing
        defer { isInstalling = false }

        do {
            // Step 1: Find hooks in app bundle
            guard let hooksSource = findHooksInBundle() else {
                throw InstallError.hooksNotFoundInBundle
            }

            // Step 2: Create config directory
            try createConfigDirectory()

            // Step 3: Copy hook scripts
            try copyHookScripts(from: hooksSource)

            // Step 4: Make scripts executable
            try makeScriptsExecutable()

            // Step 5: Update Claude settings.json
            try updateClaudeSettings()

            // Step 6: Install Claude Code commands (slash commands)
            try installClaudeCommands()

            // Verify installation
            _ = await checkSetup()
            return setupStatus == .installed

        } catch let error as InstallError {
            installError = error.localizedDescription
            _ = await checkSetup()
            return false
        } catch {
            installError = error.localizedDescription
            _ = await checkSetup()
            return false
        }
    }

    private func findHooksInBundle() -> URL? {
        // Check app bundle Resources directly (hooks are copied to Resources root)
        if let bundleResources = Bundle.main.resourceURL {
            let hookScript = bundleResources.appendingPathComponent("notch-hook.sh")
            if FileManager.default.fileExists(atPath: hookScript.path) {
                return bundleResources
            }
        }

        // Check common app locations
        let locations = [
            "/Applications/cookinn.notch.app/Contents/Resources",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/cookinn.notch.app/Contents/Resources"
        ]

        for path in locations {
            let hookScript = "\(path)/notch-hook.sh"
            if FileManager.default.fileExists(atPath: hookScript) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func createConfigDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir.path) {
            do {
                try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            } catch {
                throw InstallError.failedToCreateDirectory(error)
            }
        }
    }

    private func copyHookScripts(from source: URL) throws {
        let fm = FileManager.default

        do {
            let contents = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            let shellScripts = contents.filter { $0.pathExtension == "sh" }

            for script in shellScripts {
                let destination = configDir.appendingPathComponent(script.lastPathComponent)

                // Remove existing file if present
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }

                try fm.copyItem(at: script, to: destination)
            }
        } catch {
            throw InstallError.failedToCopyHooks(error)
        }
    }

    private func makeScriptsExecutable() throws {
        let fm = FileManager.default

        do {
            let contents = try fm.contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil)
            let shellScripts = contents.filter { $0.pathExtension == "sh" }

            for script in shellScripts {
                // Set executable permissions (755)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            }
        } catch {
            // Non-fatal, scripts might still work
        }
    }

    private func updateClaudeSettings() throws {
        let fm = FileManager.default

        // Create .claude directory if needed
        if !fm.fileExists(atPath: claudeDir.path) {
            do {
                try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            } catch {
                throw InstallError.failedToCreateDirectory(error)
            }
        }

        // Load existing settings or start with empty object
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: claudeSettings.path) {
            if let data = fm.contents(atPath: claudeSettings.path) {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw InstallError.invalidSettingsJson
                }
                settings = json
            }
        }

        // Get or create hooks dictionary
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Our hook script path and entry (no matcher = match all events)
        let ourHookPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.config/cookinn-notch/notch-hook.sh"
        let hookEntry: [String: Any] = [
            "hooks": [
                ["type": "command", "command": ourHookPath]
            ]
        ]

        // Add our hook to each hook type if not already present
        for hookType in hookTypes {
            var existingHooks = hooks[hookType] as? [[String: Any]] ?? []

            // Check if our hook is already registered (handle both new object and legacy string formats)
            let alreadyExists = existingHooks.contains { entry in
                if let hookObjects = entry["hooks"] as? [[String: Any]] {
                    return hookObjects.contains { obj in
                        (obj["command"] as? String) == ourHookPath
                    }
                } else if let hookPaths = entry["hooks"] as? [String] {
                    // Legacy format fallback
                    return hookPaths.contains(ourHookPath)
                }
                return false
            }

            if !alreadyExists {
                existingHooks.append(hookEntry)
                hooks[hookType] = existingHooks
            }
        }

        settings["hooks"] = hooks

        // Write updated settings
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeSettings)
        } catch {
            throw InstallError.failedToUpdateSettings(error)
        }
    }

    private func checkSettingsJson() -> Bool {
        guard let data = FileManager.default.contents(atPath: claudeSettings.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Check if any hook array contains our path (handle both new object and legacy string formats)
        for (_, value) in hooks {
            if let hookArray = value as? [[String: Any]] {
                for hook in hookArray {
                    // Check new object format
                    if let hookObjects = hook["hooks"] as? [[String: Any]] {
                        if hookObjects.contains(where: { ($0["command"] as? String)?.contains("cookinn-notch") == true }) {
                            return true
                        }
                    }
                    // Check legacy string format
                    if let hookPaths = hook["hooks"] as? [String],
                       hookPaths.contains(where: { $0.contains("cookinn-notch") }) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func installClaudeCommands() throws {
        let fm = FileManager.default
        let commandsDir = claudeDir.appendingPathComponent("commands")

        // Create commands directory if needed
        if !fm.fileExists(atPath: commandsDir.path) {
            try fm.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        }

        // Install send-to-notch command
        let sendToNotch = """
        Pin this Claude Code session to the cookinn.notch display.

        Run this command:
        ```bash
        ~/.config/cookinn-notch/send-to-notch.sh
        ```

        Then confirm to the user that the session has been pinned to the notch display.
        """
        let sendToNotchPath = commandsDir.appendingPathComponent("send-to-notch.md")
        try sendToNotch.write(to: sendToNotchPath, atomically: true, encoding: .utf8)

        // Install remove-from-notch command
        let removeFromNotch = """
        Unpin all sessions from the cookinn.notch display.

        Run this command:
        ```bash
        ~/.config/cookinn-notch/remove-from-notch.sh
        ```

        Then confirm to the user that the sessions have been unpinned from the notch display.
        """
        let removeFromNotchPath = commandsDir.appendingPathComponent("remove-from-notch.md")
        try removeFromNotch.write(to: removeFromNotchPath, atomically: true, encoding: .utf8)
    }
}
