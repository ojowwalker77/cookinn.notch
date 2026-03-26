//
//  FileWatcherManager.swift
//  cookinn.notch
//
//  FSEvents-based file system watcher for Ralph loop detection
//  Replaces polling with real-time notifications, reducing I/O by ~95%
//

import Foundation
import CoreServices

/// File watcher using FSEvents - NOT MainActor isolated due to C callback requirements
final class FileWatcherManager: @unchecked Sendable {
    static let shared = FileWatcherManager()

    // Directories to watch for Ralph loop state files
    private static let watchDirectories = ["~/www", "~/projects", "~/code", "~/dev", "~/Developer"]

    // FSEvents stream reference
    private var streamRef: FSEventStreamRef?
    private var isWatching = false

    // Dedicated queue for FSEvents
    private let eventQueue = DispatchQueue(label: "com.cookinn.notch.fsevents", qos: .utility)

    // Debounce: collect changed paths and process in batches
    private var pendingChangedPaths: Set<String> = []
    private let pendingPathsLock = NSLock()
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5

    private init() {}

    // MARK: - Public API

    func startWatching() {
        eventQueue.async { [weak self] in
            self?.startWatchingOnQueue()
        }
    }

    private func startWatchingOnQueue() {
        guard !isWatching else { return }

        // Check setting on main actor
        let shouldWatch = DispatchQueue.main.sync {
            NotchState.shared.showRalphLoops
        }
        guard shouldWatch else { return }

        let paths = Self.watchDirectories.compactMap { dir -> String? in
            let expanded = NSString(string: dir).expandingTildeInPath
            return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
        }

        guard !paths.isEmpty else { return }

        // Create context - use a simple pointer wrapper
        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: contextPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create FSEvents stream with C callback
        streamRef = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // Latency: 1 second batching
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream = streamRef else { return }

        FSEventStreamSetDispatchQueue(stream, eventQueue)
        FSEventStreamStart(stream)
        isWatching = true

        // Initial scan on main actor
        DispatchQueue.main.async {
            RalphLoopManager.shared.performFullScan()
        }
    }

    func stopWatching() {
        eventQueue.async { [weak self] in
            self?.stopWatchingOnQueue()
        }
    }

    private func stopWatchingOnQueue() {
        guard isWatching, let stream = streamRef else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        isWatching = false

        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        pendingPathsLock.lock()
        pendingChangedPaths.removeAll()
        pendingPathsLock.unlock()
    }

    // MARK: - Event Handling (called from C callback on eventQueue)

    fileprivate func handleEvents(paths: [String]) {
        // Filter and collect ralph-related paths
        var newPaths: [String] = []
        for path in paths {
            if isRalphRelatedPath(path), let projectPath = extractProjectPath(from: path) {
                newPaths.append(projectPath)
            }
        }

        guard !newPaths.isEmpty else { return }

        // Thread-safe add to pending
        pendingPathsLock.lock()
        for path in newPaths {
            pendingChangedPaths.insert(path)
        }
        pendingPathsLock.unlock()

        // Debounce: cancel previous and schedule new
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.processPendingChanges()
        }
        debounceWorkItem = workItem
        eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func processPendingChanges() {
        pendingPathsLock.lock()
        let paths = Array(pendingChangedPaths)
        pendingChangedPaths.removeAll()
        pendingPathsLock.unlock()

        guard !paths.isEmpty else { return }

        // Dispatch to main actor for RalphLoopManager
        DispatchQueue.main.async {
            RalphLoopManager.shared.checkPaths(paths)
        }
    }

    // MARK: - Path Analysis

    private func isRalphRelatedPath(_ path: String) -> Bool {
        // OpenCode Ralph: .opencode/ralph-loop.state.json
        if path.contains(".opencode") && path.contains("ralph-loop.state.json") {
            return true
        }
        // OpenCode directory itself
        if path.hasSuffix(".opencode") {
            return true
        }
        // Claude Code Ralph: status.json or PROMPT.md at project root
        if path.hasSuffix("/status.json") || path.hasSuffix("/PROMPT.md") {
            return true
        }
        return false
    }

    private func extractProjectPath(from filePath: String) -> String? {
        let url = URL(fileURLWithPath: filePath)
        var components = url.pathComponents

        // For .opencode/ralph-loop.state.json: go up 2 levels
        if filePath.contains(".opencode") {
            if components.count >= 3 {
                components.removeLast(2)
                return "/" + components.dropFirst().joined(separator: "/")
            }
        }

        // For status.json/PROMPT.md at root: go up 1 level
        if filePath.hasSuffix("/status.json") || filePath.hasSuffix("/PROMPT.md") {
            components.removeLast()
            return "/" + components.dropFirst().joined(separator: "/")
        }

        return nil
    }
}

// MARK: - FSEvents C Callback (outside class to avoid actor isolation issues)

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcherManager>.fromOpaque(info).takeUnretainedValue()

    // Get paths as array
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

    watcher.handleEvents(paths: paths)
}
