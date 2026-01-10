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
        request.timeoutInterval = 10

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

    /// Compare semantic versions: returns true if version1 > version2
    private func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let v1Parts = version1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = version2.split(separator: ".").compactMap { Int($0) }

        // Pad to same length
        let maxLen = max(v1Parts.count, v2Parts.count)
        let v1 = v1Parts + Array(repeating: 0, count: maxLen - v1Parts.count)
        let v2 = v2Parts + Array(repeating: 0, count: maxLen - v2Parts.count)

        for i in 0..<maxLen {
            if v1[i] > v2[i] { return true }
            if v1[i] < v2[i] { return false }
        }
        return false
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
        guard hasHomebrew else {
            // Fallback to opening releases page
            if let url = releaseURL {
                NSWorkspace.shared.open(url)
            }
            return
        }

        status = .updating

        Task.detached { [weak self] in
            guard let self = self else { return }

            let brewPath = await self.brewPath

            // Run brew update first, then upgrade
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "\(brewPath) update && \(brewPath) upgrade cookinn-notch"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let exitCode = process.terminationStatus

                await MainActor.run {
                    if exitCode == 0 {
                        self.status = .updateComplete
                    } else {
                        // Read error output
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                        print("[UpdateChecker] Brew upgrade failed: \(output)")
                        self.status = .error("Upgrade failed")
                    }
                }
            } catch {
                await MainActor.run {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Restart the app after update
    func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open -n '\(Bundle.main.bundlePath)'"]

        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            print("[UpdateChecker] Failed to restart: \(error)")
        }
    }
}
