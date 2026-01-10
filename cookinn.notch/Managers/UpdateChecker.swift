//
//  UpdateChecker.swift
//  cookinn.notch
//
//  Checks GitHub releases for new versions
//

import Foundation
import Combine
import AppKit

enum UpdateStatus: Equatable {
    case checking
    case upToDate(String)           // Current version
    case updateAvailable(String)    // New version available
    case updating                   // Currently updating via brew
    case updateComplete             // Update finished, restart needed
    case error(String)              // Error message

    var menuTitle: String {
        switch self {
        case .checking:
            return "Checking for updates..."
        case .upToDate(let version):
            return "v\(version) (Up to date)"
        case .updateAvailable(let newVersion):
            return "v\(newVersion) available - Click to update"
        case .updating:
            return "Updating..."
        case .updateComplete:
            return "Update complete - Restart app"
        case .error:
            return "Update check failed"
        }
    }

    var hasUpdate: Bool {
        if case .updateAvailable = self { return true }
        return false
    }

    var canRestart: Bool {
        if case .updateComplete = self { return true }
        return false
    }
}

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var status: UpdateStatus = .checking

    private let repoOwner = "ojowwalker77"
    private let repoName = "cookinn.notch"
    private var checkTask: Task<Void, Never>?
    private var periodicCheckTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // Check every 24 hours
    private let checkInterval: TimeInterval = 24 * 60 * 60

    // Current app version from bundle
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private init() {
        // Check on init
        checkForUpdates()
        // Start periodic checks
        startPeriodicChecks()
        // Setup sleep/wake observers
        setupLifecycleObservers()
    }

    deinit {
        periodicCheckTimer?.invalidate()
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func setupLifecycleObservers() {
        // Pause timer on sleep
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.periodicCheckTimer?.invalidate()
            self?.periodicCheckTimer = nil
        }

        // Resume timer on wake
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startPeriodicChecks()
                // Also check for updates after wake
                self?.checkForUpdates()
            }
        }
    }

    private func startPeriodicChecks() {
        periodicCheckTimer?.invalidate()
        periodicCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }
    }

    func checkForUpdates() {
        checkTask?.cancel()
        status = .checking

        checkTask = Task {
            await performCheck()
        }
    }

    private func performCheck() async {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

        guard let url = URL(string: urlString) else {
            status = .error("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                status = .error("Invalid response")
                return
            }

            if httpResponse.statusCode == 404 {
                // No releases yet
                status = .upToDate(currentVersion)
                return
            }

            guard httpResponse.statusCode == 200 else {
                status = .error("HTTP \(httpResponse.statusCode)")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                status = .error("Parse error")
                return
            }

            // Remove 'v' prefix if present
            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewerVersion(latestVersion, than: currentVersion) {
                status = .updateAvailable(latestVersion)
            } else {
                status = .upToDate(currentVersion)
            }

        } catch is CancellationError {
            // Task was cancelled, don't update status
            return
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Compare semantic versions with pre-release support
    /// Returns true if version1 > version2
    /// Handles: "1.6.0" > "1.6.0-beta" > "1.6.0-alpha"
    private func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let (v1Base, v1Pre) = parseVersion(version1)
        let (v2Base, v2Pre) = parseVersion(version2)

        // Compare base versions first
        let baseComparison = compareBaseVersions(v1Base, v2Base)
        if baseComparison != 0 {
            return baseComparison > 0
        }

        // Base versions equal - compare pre-release
        // No pre-release > any pre-release (e.g., "1.6.0" > "1.6.0-beta")
        if v1Pre == nil && v2Pre != nil { return true }
        if v1Pre != nil && v2Pre == nil { return false }
        if v1Pre == nil && v2Pre == nil { return false }

        // Both have pre-release - compare lexicographically
        return v1Pre! > v2Pre!
    }

    /// Parse version into base and pre-release components
    /// "1.6.0-beta.1" -> ([1,6,0], "beta.1")
    private func parseVersion(_ version: String) -> (base: [Int], preRelease: String?) {
        let parts = version.split(separator: "-", maxSplits: 1)
        let basePart = String(parts[0])
        let preRelease = parts.count > 1 ? String(parts[1]) : nil

        let baseNumbers = basePart.split(separator: ".").compactMap { Int($0) }
        return (baseNumbers, preRelease)
    }

    /// Compare base version arrays
    /// Returns: positive if v1 > v2, negative if v1 < v2, 0 if equal
    private func compareBaseVersions(_ v1: [Int], _ v2: [Int]) -> Int {
        let maxLen = max(v1.count, v2.count)
        let v1Padded = v1 + Array(repeating: 0, count: maxLen - v1.count)
        let v2Padded = v2 + Array(repeating: 0, count: maxLen - v2.count)

        for i in 0..<maxLen {
            if v1Padded[i] > v2Padded[i] { return 1 }
            if v1Padded[i] < v2Padded[i] { return -1 }
        }
        return 0
    }

    /// URL to download the latest release
    var releaseURL: URL? {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")
    }

    // MARK: - Brew Update

    /// Check if Homebrew is available
    var hasHomebrew: Bool {
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
    }

    /// Path to brew executable
    private var brewPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        return "/usr/local/bin/brew"
    }

    /// Run brew upgrade to update the app
    func performBrewUpgrade() {
        // Validate state before proceeding
        guard case .updateAvailable = status else { return }

        guard hasHomebrew else {
            // Fallback to opening releases page
            if let url = releaseURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        status = .updating

        // Capture brewPath before detached task to avoid MainActor context switch
        let brewExecutable = brewPath

        Task.detached { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "\"$1\" update && \"$1\" upgrade cookinn-notch", "--", brewExecutable]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Collect output asynchronously to prevent deadlock
            var outputData = Data()
            let outputLock = NSLock()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputLock.lock()
                    outputData.append(data)
                    outputLock.unlock()
                }
            }

            do {
                try process.run()
                process.waitUntilExit()

                // Stop reading
                pipe.fileHandleForReading.readabilityHandler = nil

                let exitCode = process.terminationStatus
                outputLock.lock()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                outputLock.unlock()

                await MainActor.run {
                    if exitCode == 0 {
                        self.status = .updateComplete
                    } else {
                        print("[UpdateChecker] Brew upgrade failed: \(output)")
                        self.status = .error("Upgrade failed")
                    }
                }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Restart the app after update
    func restartApp() {
        // Validate state before proceeding
        guard case .updateComplete = status else { return }

        let bundlePath = Bundle.main.bundlePath

        // Use positional parameter $1 to avoid shell injection
        // The bundle path is passed as a separate argument, not interpolated into the command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open -n \"$1\"", "--", bundlePath]

        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            print("[UpdateChecker] Failed to restart: \(error)")
        }
    }
}
