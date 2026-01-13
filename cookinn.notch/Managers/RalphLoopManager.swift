//
//  RalphLoopManager.swift
//  cookinn.notch
//
//  Handles detection of Ralph loops from both Claude Code and OpenCode
//

import Foundation

@MainActor
final class RalphLoopManager {
    static let shared = RalphLoopManager()

    // MARK: - Configuration

    /// Directories to scan for Ralph loops (first-level subdirectories only)
    private static let scanDirectories: [String] = [
        "~/www",
        "~/projects",
        "~/code",
        "~/dev",
        "~/Developer"
    ]

    // MARK: - State

    /// Cache of known project paths with Ralph loops
    private var knownRalphPaths: Set<String> = []

    /// Last time we did a full directory scan
    private var lastFullScanTime: Date = .distantPast

    /// How often to do a full scan for new Ralph loops (seconds)
    private let fullScanInterval: TimeInterval = 30.0

    // MARK: - Initialization

    private init() {}

    // MARK: - Detection Entry Point

    /// Main entry point - called periodically by ClaudeCodeServer
    func checkRalphLoops() {
        // Skip if Ralph loops are disabled in settings
        guard NotchState.shared.showRalphLoops else { return }

        // Quick check: monitor known paths every tick
        checkKnownPaths()

        // Full scan: discover new Ralph loops periodically
        let now = Date()
        if now.timeIntervalSince(lastFullScanTime) > fullScanInterval {
            lastFullScanTime = now
            discoverNewRalphLoops()
        }
    }

    // MARK: - Known Path Monitoring

    /// Check known Ralph paths (fast, runs every tick)
    private func checkKnownPaths() {
        var pathsToRemove: [String] = []

        for projectPath in knownRalphPaths {
            // Try OpenCode Ralph first
            if let openCodeState = detectOpenCodeRalph(at: projectPath) {
                if openCodeState.active {
                    NotchState.shared.ensureOpenCodeRalphSession(forProjectPath: projectPath, state: openCodeState)
                } else {
                    NotchState.shared.updateOpenCodeRalphState(forProjectPath: projectPath, state: openCodeState)
                }
                continue
            }

            // Try Claude Code Ralph
            if let claudeCodeState = detectClaudeCodeRalph(at: projectPath) {
                if claudeCodeState.isActive {
                    NotchState.shared.ensureClaudeCodeRalphSession(forProjectPath: projectPath, state: claudeCodeState)
                } else {
                    NotchState.shared.updateClaudeCodeRalphState(forProjectPath: projectPath, state: claudeCodeState)
                }
                continue
            }

            // No Ralph state found - clear and remove from known paths
            NotchState.shared.updateOpenCodeRalphState(forProjectPath: projectPath, state: nil)
            NotchState.shared.updateClaudeCodeRalphState(forProjectPath: projectPath, state: nil)
            pathsToRemove.append(projectPath)
        }

        for path in pathsToRemove {
            knownRalphPaths.remove(path)
        }
    }

    // MARK: - Discovery

    /// Discover new Ralph loops by scanning directories (slower, runs periodically)
    private func discoverNewRalphLoops() {
        let fileManager = FileManager.default

        for baseDir in Self.scanDirectories {
            let expandedPath = NSString(string: baseDir).expandingTildeInPath

            guard fileManager.fileExists(atPath: expandedPath) else { continue }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: expandedPath) else { continue }

            for item in contents {
                let projectPath = (expandedPath as NSString).appendingPathComponent(item)
                var isDirectory: ObjCBool = false

                guard fileManager.fileExists(atPath: projectPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                // Check for OpenCode Ralph
                if let openCodeState = detectOpenCodeRalph(at: projectPath), openCodeState.active {
                    knownRalphPaths.insert(projectPath)
                    NotchState.shared.ensureOpenCodeRalphSession(forProjectPath: projectPath, state: openCodeState)
                    continue
                }

                // Check for Claude Code Ralph
                if let claudeCodeState = detectClaudeCodeRalph(at: projectPath), claudeCodeState.isActive {
                    knownRalphPaths.insert(projectPath)
                    NotchState.shared.ensureClaudeCodeRalphSession(forProjectPath: projectPath, state: claudeCodeState)
                }
            }
        }
    }

    // MARK: - OpenCode Ralph Detection

    /// Detect OpenCode Ralph loop state (from .opencode/ralph-loop.state.json)
    private func detectOpenCodeRalph(at projectPath: String) -> OpenCodeRalphState? {
        let stateFilePath = (projectPath as NSString).appendingPathComponent(".opencode/ralph-loop.state.json")
        let fileURL = URL(fileURLWithPath: stateFilePath)

        guard FileManager.default.fileExists(atPath: stateFilePath),
              let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(OpenCodeRalphState.self, from: data) else {
            return nil
        }

        return state
    }

    // MARK: - Claude Code Ralph Detection

    /// Detect Claude Code Ralph loop state (from status.json + PROMPT.md indicator)
    private func detectClaudeCodeRalph(at projectPath: String) -> ClaudeCodeRalphState? {
        let fileManager = FileManager.default

        // Check for PROMPT.md (indicator that this is a Ralph project)
        let promptPath = (projectPath as NSString).appendingPathComponent("PROMPT.md")
        guard fileManager.fileExists(atPath: promptPath) else { return nil }

        // Check for status.json
        let statusPath = (projectPath as NSString).appendingPathComponent("status.json")
        let fileURL = URL(fileURLWithPath: statusPath)

        guard fileManager.fileExists(atPath: statusPath),
              let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(ClaudeCodeRalphState.self, from: data) else {
            return nil
        }

        // Verify the status.json was recently updated (within last 90 seconds)
        // Claude Code Ralph updates status.json frequently during active loops
        // If it hasn't been updated, the loop likely finished or crashed
        if let modDate = try? fileManager.attributesOfItem(atPath: statusPath)[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modDate)
            if age > 90 { // 90 seconds - if no update, loop is dead
                return nil
            }
        }

        return state
    }
}
