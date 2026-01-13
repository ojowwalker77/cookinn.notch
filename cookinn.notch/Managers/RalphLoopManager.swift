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
    private var lastFullScanTime: Date = .distantPast
    private let fullScanInterval: TimeInterval = 30.0

    private init() {}

    func checkRalphLoops() {
        guard NotchState.shared.showRalphLoops else { return }
        checkKnownPaths()

        let now = Date()
        if now.timeIntervalSince(lastFullScanTime) > fullScanInterval {
            lastFullScanTime = now
            discoverNewRalphLoops()
        }
    }

    private func checkKnownPaths() {
        var pathsToRemove: [String] = []

        for projectPath in knownRalphPaths {
            if let state = detectOpenCodeRalph(at: projectPath) {
                if state.active {
                    NotchState.shared.ensureOpenCodeRalphSession(forProjectPath: projectPath, state: state)
                } else {
                    NotchState.shared.updateOpenCodeRalphState(forProjectPath: projectPath, state: state)
                }
                continue
            }

            if let state = detectClaudeCodeRalph(at: projectPath) {
                if state.isActive {
                    NotchState.shared.ensureClaudeCodeRalphSession(forProjectPath: projectPath, state: state)
                } else {
                    NotchState.shared.updateClaudeCodeRalphState(forProjectPath: projectPath, state: state)
                }
                continue
            }

            NotchState.shared.updateOpenCodeRalphState(forProjectPath: projectPath, state: nil)
            NotchState.shared.updateClaudeCodeRalphState(forProjectPath: projectPath, state: nil)
            pathsToRemove.append(projectPath)
        }

        for path in pathsToRemove {
            knownRalphPaths.remove(path)
        }
    }

    private func discoverNewRalphLoops() {
        let fm = FileManager.default

        for baseDir in Self.scanDirectories {
            let expandedPath = NSString(string: baseDir).expandingTildeInPath
            guard fm.fileExists(atPath: expandedPath),
                  let contents = try? fm.contentsOfDirectory(atPath: expandedPath) else { continue }

            for item in contents {
                let projectPath = (expandedPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }

                if let state = detectOpenCodeRalph(at: projectPath), state.active {
                    knownRalphPaths.insert(projectPath)
                    NotchState.shared.ensureOpenCodeRalphSession(forProjectPath: projectPath, state: state)
                    continue
                }

                if let state = detectClaudeCodeRalph(at: projectPath), state.isActive {
                    knownRalphPaths.insert(projectPath)
                    NotchState.shared.ensureClaudeCodeRalphSession(forProjectPath: projectPath, state: state)
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
