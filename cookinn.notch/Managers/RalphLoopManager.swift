//
//  RalphLoopManager.swift
//  cookinn.notch
//

import Foundation

@MainActor
final class RalphLoopManager {
    static let shared = RalphLoopManager()

    private static let scanDirectories = ["~/www", "~/projects", "~/code", "~/dev", "~/Developer"]
    private static let staleThreshold: TimeInterval = 90.0

    private var knownRalphPaths: Set<String> = []

    // FSEvents-based watching (primary) vs polling fallback
    private var useFileWatcher: Bool = true
    private var lastFullScanTime: Date = .distantPast
    private let fullScanInterval: TimeInterval = 60.0  // Increased: FSEvents handles most updates

    private init() {}

    // MARK: - Public API

    /// Called periodically by ClaudeCodeServer (fallback/stale check only)
    func checkRalphLoops() {
        guard NotchState.shared.showRalphLoops else {
            FileWatcherManager.shared.stopWatching()
            return
        }

        // Start FSEvents watcher if not running
        if useFileWatcher {
            FileWatcherManager.shared.startWatching()
        }

        // Check known paths for staleness
        checkKnownPaths()

        // Fallback full scan (less frequent since FSEvents handles most changes)
        let now = Date()
        if now.timeIntervalSince(lastFullScanTime) > fullScanInterval {
            lastFullScanTime = now
            discoverNewRalphLoops()
        }
    }

    /// Called by FileWatcherManager when specific paths change
    func checkPaths(_ paths: [String]) {
        guard NotchState.shared.showRalphLoops else { return }

        for projectPath in paths {
            // Validate path is within allowed directories
            let isAllowed = Self.scanDirectories.contains { baseDir in
                let expanded = NSString(string: baseDir).expandingTildeInPath
                return projectPath.hasPrefix(expanded)
            }
            guard isAllowed else { continue }

            checkSinglePath(projectPath)
        }
    }

    /// Perform a full directory scan (called by FileWatcherManager on startup)
    func performFullScan() {
        lastFullScanTime = Date()
        discoverNewRalphLoops()
    }

    // MARK: - Path Checking

    private func checkSinglePath(_ projectPath: String) {
        // Try OpenCode Ralph first
        if let state = detectOpenCodeRalph(at: projectPath) {
            knownRalphPaths.insert(projectPath)
            if state.active {
                NotchState.shared.ensureOpenCodeRalphSession(forProjectPath: projectPath, state: state)
            } else {
                NotchState.shared.updateOpenCodeRalphState(forProjectPath: projectPath, state: state)
            }
            return
        }

        // Try Claude Code Ralph
        if let state = detectClaudeCodeRalph(at: projectPath) {
            knownRalphPaths.insert(projectPath)
            if state.isActive {
                NotchState.shared.ensureClaudeCodeRalphSession(forProjectPath: projectPath, state: state)
            } else {
                NotchState.shared.updateClaudeCodeRalphState(forProjectPath: projectPath, state: state)
            }
            return
        }

        // No Ralph state found - clean up if previously known
        if knownRalphPaths.contains(projectPath) {
            NotchState.shared.updateOpenCodeRalphState(forProjectPath: projectPath, state: nil)
            NotchState.shared.updateClaudeCodeRalphState(forProjectPath: projectPath, state: nil)
            knownRalphPaths.remove(projectPath)
        }
    }

    private func checkKnownPaths() {
        // Check all known paths using the unified check method
        for projectPath in Array(knownRalphPaths) {
            checkSinglePath(projectPath)
        }
    }

    private func discoverNewRalphLoops() {
        let fm = FileManager.default

        for baseDir in Self.scanDirectories {
            let expandedPath = NSString(string: baseDir).expandingTildeInPath
            guard fm.fileExists(atPath: expandedPath),
                  let contents = try? fm.contentsOfDirectory(atPath: expandedPath) else { continue }

            for item in contents {
                // Skip hidden files and entries with path traversal
                guard !item.hasPrefix("."), !item.contains("..") else { continue }

                let projectPath = (expandedPath as NSString).appendingPathComponent(item)

                // Validate resolved path stays within scan directory
                guard let validPath = NotchState.shared.validatePathWithinDirectory(projectPath, allowedBase: expandedPath) else { continue }

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: validPath, isDirectory: &isDir), isDir.boolValue else { continue }

                if let state = detectOpenCodeRalph(at: validPath), state.active {
                    knownRalphPaths.insert(validPath)
                    NotchState.shared.ensureOpenCodeRalphSession(forProjectPath: validPath, state: state)
                    continue
                }

                if let state = detectClaudeCodeRalph(at: validPath), state.isActive {
                    knownRalphPaths.insert(validPath)
                    NotchState.shared.ensureClaudeCodeRalphSession(forProjectPath: validPath, state: state)
                }
            }
        }
    }

    private func detectOpenCodeRalph(at projectPath: String) -> OpenCodeRalphState? {
        let fm = FileManager.default
        let path = (projectPath as NSString).appendingPathComponent(".opencode/ralph-loop.state.json")

        guard fm.fileExists(atPath: path) else { return nil }

        // Check staleness before decoding to avoid reading partially-written or abandoned state files
        guard let modDate = try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date,
              Date().timeIntervalSince(modDate) <= Self.staleThreshold else { return nil }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let state = try? JSONDecoder().decode(OpenCodeRalphState.self, from: data) else { return nil }
        return state
    }

    private func detectClaudeCodeRalph(at projectPath: String) -> ClaudeCodeRalphState? {
        let fm = FileManager.default
        let promptPath = (projectPath as NSString).appendingPathComponent("PROMPT.md")
        let statusPath = (projectPath as NSString).appendingPathComponent("status.json")
        
        guard fm.fileExists(atPath: promptPath), fm.fileExists(atPath: statusPath) else { return nil }

        // Check staleness before decoding to avoid reading partially-written or abandoned state files
        guard let modDate = try? fm.attributesOfItem(atPath: statusPath)[.modificationDate] as? Date,
              Date().timeIntervalSince(modDate) <= Self.staleThreshold else { return nil }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusPath)),
              let state = try? JSONDecoder().decode(ClaudeCodeRalphState.self, from: data) else { return nil }
        return state
    }
}
