//
//  ClaudeCodeModels.swift
//  cookinn.notch
//
//  Comprehensive models for Claude Code CLI hook events
//

import Foundation
import Combine
import SwiftUI

// MARK: - OpenCode Ralph Loop State (from .opencode/ralph-loop.state.json)

struct OpenCodeRalphState: Codable, Equatable {
    let active: Bool
    let iteration: Int
    let maxIterations: Int
    let completionPromise: String
    let prompt: String
    let startedAt: String
    let model: String

    /// Parse startedAt ISO string to Date
    var startDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: startedAt) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: startedAt)
    }

    /// Display string for iteration progress (e.g., "3/10" or "3/∞")
    var iterationDisplay: String {
        if maxIterations > 0 {
            return "\(iteration)/\(maxIterations)"
        }
        return "\(iteration)/∞"
    }
}

// MARK: - Claude Code Ralph Loop State (from status.json)

struct ClaudeCodeRalphState: Codable, Equatable {
    let timestamp: String
    let loop_count: Int
    let calls_made_this_hour: Int
    let max_calls_per_hour: Int
    let last_action: String
    let status: String  // "success", "running", "error"
    let exit_reason: String
    let next_reset: String

    /// Only "running" is active; "success" and "error" are terminal states
    var isActive: Bool {
        status == "running"
    }

    /// Display string for iteration (just count, no max for Claude Code Ralph)
    var iterationDisplay: String {
        "\(loop_count)"
    }

    /// Parse timestamp to Date
    var timestampDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }
}

// MARK: - Hook Event Payload (internal normalized format)

struct HookPayload {
    let event: String
    let sessionId: String
    let cwd: String?
    let projectName: String?
    let permissionMode: String?
    let toolName: String?
    let toolUseId: String?
    let toolInput: [String: AnyCodable]?
    let toolResponse: [String: AnyCodable]?
    let source: String?
    let reason: String?
    let message: String?
    let notificationType: String?
    let usage: TokenUsage?
    let contextPercent: Double?
    let agentType: String?
    let modelId: String?
    let modelDisplayName: String?
    let costUsd: Double?
    let agentId: String?
    let teammateName: String?
    let teamName: String?
    let taskId: String?
    let taskSubject: String?
    let oldCwd: String?
    let newCwd: String?
}

// MARK: - Native Hook Payload (from Claude Code HTTP hooks)

struct NativeContextWindow: Codable {
    let used_percentage: Double?
}

struct NativeCostInfo: Codable {
    let total_cost_usd: Double?
}

struct NativeModelInfo: Codable {
    let id: String?
    let display_name: String?
}

struct NativeHookPayload: Codable {
    let hook_event_name: String
    let session_id: String
    let cwd: String?
    let tool_name: String?
    let tool_use_id: String?
    let tool_input: [String: AnyCodable]?
    let tool_response: [String: AnyCodable]?
    let permission_mode: String?
    let source: String?
    let reason: String?
    let message: String?
    let notification_type: String?
    let agent_type: String?
    let agent_id: String?
    let transcript_path: String?
    let context_window: NativeContextWindow?
    let cost: NativeCostInfo?
    let model: NativeModelInfo?
    let teammate_name: String?
    let team_name: String?
    let task_id: String?
    let task_subject: String?
    let task_description: String?
    let old_cwd: String?
    let new_cwd: String?
    let usage: TokenUsage?

    func toHookPayload() -> HookPayload {
        let projectName: String? = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        return HookPayload(
            event: hook_event_name,
            sessionId: session_id,
            cwd: cwd,
            projectName: projectName,
            permissionMode: permission_mode,
            toolName: tool_name,
            toolUseId: tool_use_id,
            toolInput: tool_input,
            toolResponse: tool_response,
            source: source,
            reason: reason,
            message: message,
            notificationType: notification_type,
            usage: usage,
            contextPercent: context_window?.used_percentage,
            agentType: agent_type,
            modelId: model?.id,
            modelDisplayName: model?.display_name,
            costUsd: cost?.total_cost_usd,
            agentId: agent_id,
            teammateName: teammate_name,
            teamName: team_name,
            taskId: task_id,
            taskSubject: task_subject,
            oldCwd: old_cwd,
            newCwd: new_cwd
        )
    }
}

// MARK: - Token Usage (from Claude Code Stop event)

struct TokenUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    var totalTokens: Int {
        (inputTokens ?? 0) + (outputTokens ?? 0)
    }
}

// MARK: - Tool Display Info

struct ToolDisplayInfo {
    let name: String
    let displayName: String
    let detail: String
    let icon: String
    let color: ToolColor

    enum ToolColor {
        case cyan, green, yellow, orange, red, purple, blue, indigo, pink, teal, mint, gray
    }
}

// MARK: - Active Tool State

struct ActiveTool: Identifiable, Equatable {
    let id: String              // tool_use_id
    let name: String            // tool_name
    let input: ToolInput        // parsed tool_input
    let startTime: Date
    var endTime: Date?
    var response: ToolResponse? // parsed tool_response

    // P1.6: Cached resolved info to avoid repeated lookups
    private let _resolved: ResolvedToolInfo

    init(id: String, name: String, input: ToolInput, startTime: Date, endTime: Date? = nil, response: ToolResponse? = nil) {
        self.id = id
        self.name = name
        self.input = input
        self.startTime = startTime
        self.endTime = endTime
        self.response = response
        // P1.6: Cache resolved info at creation time
        self._resolved = ConfigManager.shared.resolveToolInfo(for: name)
    }

    var isComplete: Bool { endTime != nil }
    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }

    var displayInfo: ToolDisplayInfo {
        ToolDisplayInfo(
            name: name,
            displayName: displayName,
            detail: input.displayDetail,
            icon: "circle.fill",  // Using simple icon, color conveys meaning
            color: toolColorEnum
        )
    }

    var displayName: String {
        _resolved.displayName
    }

    var pattern: String {
        _resolved.pattern
    }

    var intensity: Int {
        _resolved.intensity
    }

    var attention: String {
        _resolved.attention
    }

    var color: Color {
        ConfigManager.shared.swiftUIColor(for: _resolved.color)
    }

    private var toolColorEnum: ToolDisplayInfo.ToolColor {
        switch _resolved.color.lowercased() {
        case "cyan": return .cyan
        case "green": return .green
        case "yellow", "amber": return .yellow
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "blue": return .blue
        case "indigo", "violet": return .indigo
        case "pink": return .pink
        case "teal": return .teal
        case "mint": return .mint
        default: return .gray
        }
    }
}

// MARK: - Tool Input (parsed from toolInput JSON)

struct ToolInput: Equatable {
    let filePath: String?
    let command: String?
    let pattern: String?
    let content: String?
    let query: String?
    let url: String?
    let prompt: String?
    let description: String?
    // P1.6: Dropped raw dictionary after parsing to reduce memory footprint

    init(from dict: [String: AnyCodable]?) {
        guard let dict = dict else {
            self.filePath = nil
            self.command = nil
            self.pattern = nil
            self.content = nil
            self.query = nil
            self.url = nil
            self.prompt = nil
            self.description = nil
            return
        }

        self.filePath = dict["file_path"]?.value as? String
        self.command = dict["command"]?.value as? String
        self.pattern = dict["pattern"]?.value as? String
        self.content = dict["content"]?.value as? String
        self.query = dict["query"]?.value as? String
        self.url = dict["url"]?.value as? String
        self.prompt = dict["prompt"]?.value as? String
        self.description = dict["description"]?.value as? String
        // P1.6: Don't store raw dict - we've extracted what we need
    }

    var displayDetail: String {
        // Priority order for what to show
        if let cmd = command {
            return truncate(cmd, maxLen: 50)
        }
        if let path = filePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let pat = pattern {
            return truncate(pat, maxLen: 40)
        }
        if let q = query {
            return truncate(q, maxLen: 40)
        }
        if let u = url {
            return URL(string: u)?.host ?? truncate(u, maxLen: 40)
        }
        if let p = prompt {
            return truncate(p, maxLen: 40)
        }
        if let d = description {
            return truncate(d, maxLen: 40)
        }
        return ""
    }

    private func truncate(_ s: String, maxLen: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first ?? s
        if trimmed.count > maxLen {
            return String(trimmed.prefix(maxLen)) + "..."
        }
        return trimmed
    }

    static func == (lhs: ToolInput, rhs: ToolInput) -> Bool {
        lhs.filePath == rhs.filePath &&
        lhs.command == rhs.command &&
        lhs.pattern == rhs.pattern
    }
}

// MARK: - Tool Response (parsed from toolResponse JSON)

struct ToolResponse: Equatable {
    let success: Bool?
    let filePath: String?
    let error: String?
    let output: String?

    init(from dict: [String: AnyCodable]?) {
        guard let dict = dict else {
            self.success = nil
            self.filePath = nil
            self.error = nil
            self.output = nil
            return
        }

        self.success = dict["success"]?.value as? Bool
        self.filePath = dict["filePath"]?.value as? String
        self.error = dict["error"]?.value as? String
        self.output = dict["output"]?.value as? String
    }

    static func == (lhs: ToolResponse, rhs: ToolResponse) -> Bool {
        lhs.success == rhs.success && lhs.filePath == rhs.filePath
    }
}

// MARK: - Session State

struct SessionState: Identifiable, Equatable {
    let id: String              // session_id
    let projectPath: String     // cwd
    let normalizedPath: String  // cached normalized path (avoids repeated symlink resolution)
    let projectName: String     // extracted from cwd
    var permissionMode: String  // default, plan, acceptEdits, dontAsk, bypassPermissions
    var startTime: Date
    var lastActivityTime: Date
    var activeTool: ActiveTool?
    var isActive: Bool = false  // Only true when Claude is actively responding
    var isWaitingForPermission: Bool = false  // True when Claude needs user permission (e.g., Bash)
    var isWaitingForInput: Bool = false  // True when Claude is idle waiting for user input (idle_prompt)

    var contextPercent: Double = 0.0
    var agentType: String?
    var costUsd: Double = 0.0

    // Team/agent tracking
    var activeTeammateCount: Int = 0
    var isCompacting: Bool = false

    // Ralph Loop tracking - supports both OpenCode and Claude Code Ralph
    var openCodeRalphState: OpenCodeRalphState?
    var claudeCodeRalphState: ClaudeCodeRalphState?

    /// Whether this session is in a Ralph loop (either type)
    var isInRalphLoop: Bool {
        (openCodeRalphState?.active ?? false) ||
        (claudeCodeRalphState?.isActive ?? false)
    }

    /// The iteration display string for the active Ralph loop
    var ralphIterationDisplay: String? {
        if let cc = claudeCodeRalphState, cc.isActive {
            return cc.iterationDisplay
        }
        if let oc = openCodeRalphState, oc.active {
            return oc.iterationDisplay
        }
        return nil
    }

    /// Which Ralph source is active: "claude" or "opencode"
    var ralphSource: String? {
        if claudeCodeRalphState?.isActive == true { return "claude" }
        if openCodeRalphState?.active == true { return "opencode" }
        return nil
    }

    var displayName: String {
        projectName.isEmpty ? "Claude Code" : projectName
    }

    var statusText: String {
        if isWaitingForPermission {
            return "Waiting"
        }
        if isWaitingForInput {
            return "Input"
        }
        if isCompacting {
            return "Compacting"
        }
        if let tool = activeTool {
            return tool.displayName
        }
        return isActive ? "Thinking" : "Idle"
    }

    /// Formatted cost display (e.g., "<1¢", "5¢", "$1.23")
    var formattedCost: String? {
        guard costUsd > 0 else { return nil }
        let cents = costUsd * 100
        if cents < 1 {
            return "<1¢"
        } else if cents < 100 {
            return String(format: "%.0f¢", cents)
        } else {
            return String(format: "$%.2f", costUsd)
        }
    }

    /// Display name for agent type (e.g., "Plan", "Explore")
    var agentTypeDisplay: String? {
        guard let type = agentType, !type.isEmpty else { return nil }
        // Capitalize first letter
        return type.prefix(1).uppercased() + type.dropFirst()
    }

    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        // Compare all fields that affect UI display
        lhs.id == rhs.id &&
        lhs.activeTool == rhs.activeTool &&
        lhs.isActive == rhs.isActive &&
        lhs.isWaitingForPermission == rhs.isWaitingForPermission &&
        lhs.isWaitingForInput == rhs.isWaitingForInput &&
        lhs.isCompacting == rhs.isCompacting &&
        lhs.activeTeammateCount == rhs.activeTeammateCount &&
        lhs.lastActivityTime == rhs.lastActivityTime &&
        lhs.contextPercent == rhs.contextPercent &&
        lhs.agentType == rhs.agentType &&
        lhs.costUsd == rhs.costUsd &&
        lhs.openCodeRalphState == rhs.openCodeRalphState &&
        lhs.claudeCodeRalphState == rhs.claudeCodeRalphState
    }
}

// MARK: - App State (singleton observable)

@MainActor @Observable
final class NotchState {
    static let shared = NotchState()

    // UserDefaults keys for persistence
    private static let pinnedPathsKey = "NotchPinnedProjectPaths"
    private static let showOnAllMonitorsKey = "NotchShowOnAllMonitors"
    private static let selectedDisplayIDKey = "NotchSelectedDisplayID"
    private static let alertSoundsEnabledKey = "NotchAlertSoundsEnabled"
    private static let showRalphLoopsKey = "NotchShowRalphLoops"
    @ObservationIgnored private var isLoadingSettings = false

    // Combine publishers for AppKit observers (replacement for @Published's $ prefix)
    // Using CurrentValueSubject to emit initial value to late subscribers
    @ObservationIgnored let showOnAllMonitorsPublisher = CurrentValueSubject<Bool, Never>(false)
    @ObservationIgnored let selectedDisplayIDPublisher = CurrentValueSubject<UInt32?, Never>(nil)
    @ObservationIgnored let isIdlePublisher = CurrentValueSubject<Bool, Never>(true)
    @ObservationIgnored let sessionsPublisher = CurrentValueSubject<[String: SessionState], Never>([:])

    // Memory pressure monitoring
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?

    // Settings (with UserDefaults persistence)
    var showOnAllMonitors: Bool = false {
        didSet {
            guard !isLoadingSettings else { return }
            UserDefaults.standard.set(showOnAllMonitors, forKey: Self.showOnAllMonitorsKey)
            showOnAllMonitorsPublisher.send(showOnAllMonitors)
        }
    }

    var alertSoundsEnabled: Bool = true {
        didSet {
            guard !isLoadingSettings else { return }
            UserDefaults.standard.set(alertSoundsEnabled, forKey: Self.alertSoundsEnabledKey)
        }
    }

    var showRalphLoops: Bool = true {
        didSet {
            guard !isLoadingSettings else { return }
            UserDefaults.standard.set(showRalphLoops, forKey: Self.showRalphLoopsKey)
        }
    }

    var selectedDisplayID: UInt32? = nil {
        didSet {
            guard !isLoadingSettings else { return }
            if let id = selectedDisplayID {
                // Safe: UInt32 (max ~4.3B) always fits in Int64 on 64-bit Macs
                UserDefaults.standard.set(Int(id), forKey: Self.selectedDisplayIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedDisplayIDKey)
            }
            selectedDisplayIDPublisher.send(selectedDisplayID)
        }
    }

    var selectedScreen: NSScreen? {
        guard let targetID = selectedDisplayID else { return nil }
        return NSScreen.screens.first { screen in
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return number.uint32Value == targetID
            }
            return false
        }
    }

    // Current state
    var sessions: [String: SessionState] = [:] {
        didSet {
            sessionsPublisher.send(sessions)
        }
    }
    var activeSessionId: String?
    var isServerRunning: Bool = false
    var hoveredDisplayIDs: Set<String> = []  // Per-screen hover state
    var lastError: String?
    var lastActivityTime: Date = Date()
    var isIdle: Bool = true {
        didSet {
            isIdlePublisher.send(isIdle)
        }
    }
    var pinnedProjectPaths: Set<String> = [] {
        didSet {
            // Persist to UserDefaults whenever pinned paths change (but not during load)
            guard !isLoadingSettings else { return }
            savePinnedPaths()
        }
    }

    // Activity timeout - clear stuck states (from config)
    var activityTimeout: TimeInterval {
        ConfigManager.shared.activityTimeout
    }

    // Computed
    var currentSession: SessionState? {
        guard let id = activeSessionId else { return nil }
        return sessions[id]
    }

    var activeTool: ActiveTool? {
        currentSession?.activeTool
    }

    var hasActivity: Bool {
        sessions.values.contains { $0.activeTool != nil }
    }

    var shouldShowNotch: Bool {
        isServerRunning && !sessions.isEmpty
    }

    private init() {
        // Load persisted settings on startup
        loadSettings()
        // Setup memory pressure monitoring
        setupMemoryPressureHandling()
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureHandling() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleMemoryPressure()
            }
        }
        memoryPressureSource?.resume()
    }

    private func handleMemoryPressure() {
        // Aggressive cleanup on memory pressure
        // 1. Clear all non-pinned sessions immediately
        let pinnedPaths = pinnedProjectPaths
        sessions = sessions.filter { _, session in
            pinnedPaths.contains(session.normalizedPath)
        }

        // 2. Clear active tool state from remaining sessions
        for id in sessions.keys {
            sessions[id]?.activeTool = nil
        }

        // 3. Limit pinned sessions to most recent 5
        if sessions.count > 5 {
            let sorted = sessions.values.sorted { $0.lastActivityTime > $1.lastActivityTime }
            let keepIds = Set(sorted.prefix(5).map { $0.id })
            sessions = sessions.filter { keepIds.contains($0.key) }
        }

        sessionsPublisher.send(sessions)
    }

    // MARK: - Persistence

    private func loadSettings() {
        isLoadingSettings = true

        // Load pinned paths
        if let array = UserDefaults.standard.stringArray(forKey: Self.pinnedPathsKey) {
            pinnedProjectPaths = Set(array)
        }

        // Load show on all monitors setting
        showOnAllMonitors = UserDefaults.standard.bool(forKey: Self.showOnAllMonitorsKey)

        // Load selected display ID
        if let savedID = UserDefaults.standard.object(forKey: Self.selectedDisplayIDKey) as? Int {
            selectedDisplayID = UInt32(savedID)
        }

        // Load alert sounds setting (default to true if not set)
        if UserDefaults.standard.object(forKey: Self.alertSoundsEnabledKey) != nil {
            alertSoundsEnabled = UserDefaults.standard.bool(forKey: Self.alertSoundsEnabledKey)
        } else {
            alertSoundsEnabled = true  // Default enabled
        }

        // Load show Ralph loops setting (default to true if not set)
        if UserDefaults.standard.object(forKey: Self.showRalphLoopsKey) != nil {
            showRalphLoops = UserDefaults.standard.bool(forKey: Self.showRalphLoopsKey)
        } else {
            showRalphLoops = true  // Default enabled
        }

        isLoadingSettings = false
    }

    private func savePinnedPaths() {
        let array = Array(pinnedProjectPaths)
        UserDefaults.standard.set(array, forKey: Self.pinnedPathsKey)
    }


    // MARK: - State Updates

    /// Thread-safe helper for atomic session updates
    /// Batches all mutations into a single dictionary write
    private func updateSession(_ id: String, _ transform: (inout SessionState) -> Void) {
        guard var session = sessions[id] else { return }
        transform(&session)
        sessions[id] = session
    }

    func handleHookEvent(_ payload: HookPayload) {
        let sessionId = payload.sessionId
        let now = Date()

        // Batch common metadata updates into single atomic operation
        if sessions[sessionId] != nil {
            updateSession(sessionId) { session in
                if let pct = payload.contextPercent, pct > 0 {
                    session.contextPercent = pct
                }
                if let cost = payload.costUsd, cost > 0 {
                    session.costUsd = cost
                }
                if let agentType = payload.agentType, !agentType.isEmpty {
                    session.agentType = agentType
                }
            }
        }

        // Clear waiting state on ANY event except Notification (which sets it)
        // This ensures immediate dismissal when user responds/rejects
        var shouldStopAlerts = false
        if payload.event != "Notification" {
            if let session = sessions[sessionId], session.isWaitingForPermission {
                let isStopEvent = payload.event == "Stop" || payload.event == "SubagentStop"
                updateSession(sessionId) { session in
                    session.isWaitingForPermission = false
                    // Only set isActive = true if NOT a Stop event (rejection)
                    if !isStopEvent {
                        session.isActive = true
                    }
                }
                // Check if any sessions still waiting (after our update)
                shouldStopAlerts = !sessions.values.contains { $0.isWaitingForPermission }
            }
        }
        // Stop alerts outside the update block to avoid nested mutations
        if shouldStopAlerts {
            AudioManager.shared.stopWaitingAlerts()
        }

        switch payload.event {
        case "PreToolUse":
            handleToolStart(payload, sessionId: sessionId, now: now)

        case "PostToolUse":
            handleToolEnd(payload, sessionId: sessionId, now: now)

        case "Stop", "SubagentStop":
            handleStop(payload, sessionId: sessionId, now: now)

        case "SessionStart":
            handleSessionStart(payload, sessionId: sessionId, now: now)

        case "SessionEnd":
            handleSessionEnd(sessionId: sessionId)

        case "Notification":
            handleNotification(payload, sessionId: sessionId)

        case "UserPromptSubmit":
            handleUserPrompt(payload, sessionId: sessionId, now: now)

        case "PermissionRequest":
            handlePermissionRequest(payload, sessionId: sessionId)

        case "CwdChanged":
            handleCwdChanged(payload, sessionId: sessionId, now: now)

        case "PreCompact":
            handlePreCompact(sessionId: sessionId, now: now)

        case "PostCompact":
            handlePostCompact(payload, sessionId: sessionId, now: now)

        case "TeammateIdle", "TaskCreated":
            handleTeammateActivity(payload, sessionId: sessionId, increment: true)

        case "TaskCompleted":
            handleTeammateActivity(payload, sessionId: sessionId, increment: false)

        case "PostToolUseFailure", "StopFailure":
            handleStop(payload, sessionId: sessionId, now: now)

        default:
            break
        }
    }

    private func handleToolStart(_ payload: HookPayload, sessionId: String, now: Date) {
        ensureSession(payload, sessionId: sessionId, now: now)

        guard let toolName = payload.toolName, !toolName.isEmpty else { return }

        // Check if we were waiting (to stop alerts) - capture before mutation
        let wasWaiting = sessions[sessionId]?.isWaitingForPermission ?? false

        let tool = ActiveTool(
            id: payload.toolUseId ?? UUID().uuidString,
            name: toolName,
            input: ToolInput(from: payload.toolInput),
            startTime: now
        )

        // Batch all session mutations
        updateSession(sessionId) { session in
            session.activeTool = tool
            session.isActive = true  // Claude is actively working
            session.isWaitingForPermission = false  // Tool started, permission granted
            session.lastActivityTime = now
        }
        activeSessionId = sessionId

        // Stop alerts only if no other sessions are still waiting
        if wasWaiting {
            let stillWaiting = sessions.values.contains { $0.isWaitingForPermission }
            if !stillWaiting {
                AudioManager.shared.stopWaitingAlerts()
            }
        }

        // Mark as active
        lastActivityTime = now
        isIdle = false
    }

    private func handleToolEnd(_ payload: HookPayload, sessionId: String, now: Date) {
        guard sessions[sessionId] != nil else { return }

        let endingToolId = payload.toolUseId

        updateSession(sessionId) { session in
            if let tool = session.activeTool {
                // Only clear if this is the currently displayed tool
                if tool.id == endingToolId {
                    session.activeTool = nil
                }
            }
            session.lastActivityTime = now
        }
    }

    private func handleStop(_ payload: HookPayload, sessionId: String, now: Date) {
        guard sessions[sessionId] != nil else { return }

        // Capture state before mutation
        let wasWaiting = sessions[sessionId]?.isWaitingForPermission ?? false

        // Agent finished responding - this is THE signal to go idle
        updateSession(sessionId) { session in
            session.activeTool = nil
            session.isActive = false  // Stop hook = idle, no other scenario
            session.isWaitingForPermission = false  // Clear waiting on stop (user rejected or responded)
            session.lastActivityTime = now
        }

        // Stop alerts only if no other sessions are still waiting
        if wasWaiting {
            let stillWaiting = sessions.values.contains { $0.isWaitingForPermission }
            if !stillWaiting {
                AudioManager.shared.stopWaitingAlerts()
            }
        }

        // Update global activity time to reset idle timer
        lastActivityTime = now
    }

    private func handleSessionStart(_ payload: HookPayload, sessionId: String, now: Date) {
        ensureSession(payload, sessionId: sessionId, now: now)
        activeSessionId = sessionId
        // No auto-pin - user must explicitly use /send-to-notch
    }

    private func handleSessionEnd(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        if activeSessionId == sessionId {
            activeSessionId = sessions.keys.first
        }
    }

    private func handleNotification(_ payload: HookPayload, sessionId: String) {
        let notifType = payload.notificationType?.lowercased() ?? ""

        // Check for permission prompt notifications (strict matching to avoid false positives)
        let isPermissionPrompt = notifType == "permission_prompt" ||
                                 notifType == "permission_required"

        // Check for idle prompt (Claude waiting for user input)
        let isIdlePrompt = notifType == "idle_prompt"

        if isPermissionPrompt {
            guard sessions[sessionId] != nil else { return }
            // Only trigger alert if not already waiting (prevent repeated sounds)
            let wasWaiting = sessions[sessionId]?.isWaitingForPermission ?? false

            updateSession(sessionId) { session in
                session.isWaitingForPermission = true
                session.isWaitingForInput = false  // Clear other waiting state
                session.isActive = false  // Claude is blocked waiting
            }

            // Start escalating alerts only on transition to waiting
            if !wasWaiting {
                AudioManager.shared.startWaitingAlerts()
            }
        } else if isIdlePrompt {
            // Claude is idle and waiting for user input (60s+ idle)
            updateSession(sessionId) { session in
                session.isWaitingForInput = true
                session.isWaitingForPermission = false
                session.isActive = false
            }
        }
    }

    private func handleUserPrompt(_ payload: HookPayload, sessionId: String, now: Date) {
        ensureSession(payload, sessionId: sessionId, now: now)

        guard sessions[sessionId] != nil else { return }

        // Capture state before mutation
        let wasWaiting = sessions[sessionId]?.isWaitingForPermission ?? false

        // Mark session as active when user submits a prompt
        updateSession(sessionId) { session in
            session.isActive = true
            session.isWaitingForPermission = false  // User responded, clear waiting state
            session.isWaitingForInput = false  // Clear idle prompt state too
            session.lastActivityTime = now
        }
        activeSessionId = sessionId

        // Stop alerts only if no other sessions are still waiting
        if wasWaiting {
            let stillWaiting = sessions.values.contains { $0.isWaitingForPermission }
            if !stillWaiting {
                AudioManager.shared.stopWaitingAlerts()
            }
        }

        // Mark as active
        lastActivityTime = now
        isIdle = false
    }

    private func handlePermissionRequest(_ payload: HookPayload, sessionId: String) {
        // Ensure session exists
        ensureSession(payload, sessionId: sessionId, now: Date())
    }

    private func handleCwdChanged(_ payload: HookPayload, sessionId: String, now: Date) {
        guard let newCwd = payload.newCwd, !newCwd.isEmpty else { return }
        ensureSession(payload, sessionId: sessionId, now: now)

        // Update the session with the new working directory
        // SessionState has let properties for path/name, so we need to replace the session
        if let existing = sessions[sessionId] {
            let newNormalized = normalizePath(newCwd)
            let newName = URL(fileURLWithPath: newCwd).lastPathComponent
            var updated = SessionState(
                id: existing.id,
                projectPath: newCwd,
                normalizedPath: newNormalized,
                projectName: newName,
                permissionMode: existing.permissionMode,
                startTime: existing.startTime,
                lastActivityTime: now
            )
            // Carry over mutable state
            updated.activeTool = existing.activeTool
            updated.isActive = existing.isActive
            updated.isWaitingForPermission = existing.isWaitingForPermission
            updated.isWaitingForInput = existing.isWaitingForInput
            updated.isCompacting = existing.isCompacting
            updated.contextPercent = existing.contextPercent
            updated.agentType = existing.agentType
            updated.costUsd = existing.costUsd
            updated.activeTeammateCount = existing.activeTeammateCount
            updated.openCodeRalphState = existing.openCodeRalphState
            updated.claudeCodeRalphState = existing.claudeCodeRalphState
            sessions[sessionId] = updated
        }
    }

    private func handlePreCompact(sessionId: String, now: Date) {
        guard sessions[sessionId] != nil else { return }
        updateSession(sessionId) { session in
            session.isCompacting = true
            session.isActive = true
            session.lastActivityTime = now
        }
        lastActivityTime = now
        isIdle = false
    }

    private func handlePostCompact(_ payload: HookPayload, sessionId: String, now: Date) {
        guard sessions[sessionId] != nil else { return }
        updateSession(sessionId) { session in
            session.isCompacting = false
            session.lastActivityTime = now
            // Update context percent with the new (lower) value after compaction
            if let pct = payload.contextPercent, pct > 0 {
                session.contextPercent = pct
            }
        }
    }

    private func handleTeammateActivity(_ payload: HookPayload, sessionId: String, increment: Bool) {
        // Find the parent session by team context or session ID
        let targetId = sessionId
        guard sessions[targetId] != nil else { return }

        updateSession(targetId) { session in
            if increment {
                session.activeTeammateCount += 1
            } else {
                session.activeTeammateCount = max(0, session.activeTeammateCount - 1)
            }
            session.lastActivityTime = Date()
        }
        lastActivityTime = Date()
        isIdle = false
    }

    private func ensureSession(_ payload: HookPayload, sessionId: String, now: Date) {
        if sessions[sessionId] == nil {
            let path = payload.cwd ?? ""
            let session = SessionState(
                id: sessionId,
                projectPath: path,
                normalizedPath: normalizePath(path),
                projectName: payload.projectName ?? "",
                permissionMode: payload.permissionMode ?? "default",
                startTime: now,
                lastActivityTime: now
            )
            sessions[sessionId] = session
            // Note: No auto-pin here - only SessionStart triggers auto-pin
        }
    }

    // MARK: - Timeout Handling

    // Idle timeout for hiding the notch (from config)
    var idleTimeout: TimeInterval {
        ConfigManager.shared.idleTimeout
    }

    // Stale session removal timeout:
    // - 30 minutes for unpinned: reasonable time for user to resume interrupted session
    // - 7 days for pinned: prevents indefinite memory growth while preserving user-pinned sessions
    private let staleSessionTimeout: TimeInterval = 30 * 60  // 30 minutes
    private let maxPinnedSessionTimeout: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    func clearStaleStates() {
        let now = Date()
        var sessionsToRemove: [String] = []
        var pathsToUnpin: [String] = []

        for (id, session) in sessions {
            let timeSinceActivity = now.timeIntervalSince(session.lastActivityTime)

            // Clear stuck states after timeout (e.g., tool started but never ended,
            // or user interrupted and Stop hook never fired)
            if timeSinceActivity > activityTimeout {
                if sessions[id]?.activeTool != nil {
                    sessions[id]?.activeTool = nil
                }
                // Check if session is in "thinking" state (isActive but no tool/waiting)
                // Thinking state has noTimeout=true, so don't clear isActive for it
                let isThinking = session.isActive && session.activeTool == nil &&
                                 !session.isWaitingForPermission && !session.isWaitingForInput

                // Also clear isActive - handles interrupt case where Stop hook doesn't fire
                // BUT skip if in thinking state (thinking has noTimeout)
                if sessions[id]?.isActive == true && !isThinking {
                    sessions[id]?.isActive = false
                }
                // Clear waiting states too - in case notification got stuck
                if sessions[id]?.isWaitingForPermission == true {
                    sessions[id]?.isWaitingForPermission = false
                    // Stop any lingering alerts
                    let stillWaiting = sessions.values.contains { $0.isWaitingForPermission }
                    if !stillWaiting {
                        AudioManager.shared.stopWaitingAlerts()
                    }
                }
                if sessions[id]?.isWaitingForInput == true {
                    sessions[id]?.isWaitingForInput = false
                }
            }

            let isInactive = !session.isActive && session.activeTool == nil && !session.isWaitingForPermission && !session.isWaitingForInput
            let isPinned = isProjectPinned(session.projectPath)

            // Remove completely stale sessions based on pinned status:
            // - Unpinned: 30 minutes
            // - Pinned: 7 days (prevents indefinite memory growth)
            let timeout = isPinned ? maxPinnedSessionTimeout : staleSessionTimeout
            let isStale = timeSinceActivity > timeout

            if isStale && isInactive {
                sessionsToRemove.append(id)
                // If pinned and being removed due to max timeout, also unpin the path
                if isPinned {
                    pathsToUnpin.append(session.projectPath)
                }
            }
        }

        // Unpin paths for sessions removed due to max timeout
        for path in pathsToUnpin {
            unpinProjectPath(path)
        }

        // Remove stale sessions
        for id in sessionsToRemove {
            sessions.removeValue(forKey: id)
            if activeSessionId == id {
                activeSessionId = sessions.keys.first
            }
        }
    }

    func checkIdleState() {
        let now = Date()
        let timeSinceActivity = now.timeIntervalSince(lastActivityTime)

        // Mark as idle after timeout, but only if not currently active
        let hasActiveWork = sessions.values.contains { $0.isActive || $0.activeTool != nil }

        if !hasActiveWork && timeSinceActivity > idleTimeout {
            if !isIdle {
                isIdle = true
            }
        }
    }

    // MARK: - Pin/Unpin by Project Path

    /// Normalize path by resolving symlinks and standardizing format
    func normalizePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        // Resolve symlinks and standardize the path
        if let resolved = try? url.resolvingSymlinksInPath() {
            return resolved.path
        }
        return (path as NSString).standardizingPath
    }

    /// Validates path stays within allowed base directory after symlink resolution
    /// Returns resolved path if valid, nil if path escapes allowed directory
    func validatePathWithinDirectory(_ path: String, allowedBase: String) -> String? {
        guard let resolvedBase = try? URL(fileURLWithPath: allowedBase).resolvingSymlinksInPath(),
              let resolvedTarget = try? URL(fileURLWithPath: path).resolvingSymlinksInPath() else {
            return nil
        }
        let basePath = resolvedBase.path
        let targetPath = resolvedTarget.path
        guard targetPath.hasPrefix(basePath + "/") || targetPath == basePath else { return nil }
        return targetPath
    }

    func pinProjectPath(_ path: String) {
        let normalized = normalizePath(path)
        pinnedProjectPaths.insert(normalized)
        isIdle = false
        lastActivityTime = Date()
    }

    func unpinProjectPath(_ path: String) {
        let normalized = normalizePath(path)
        pinnedProjectPaths.remove(normalized)

        if pinnedProjectPaths.isEmpty {
            checkIdleState()
        }
    }

    func unpinAllProjects() {
        pinnedProjectPaths.removeAll()
    }

    func isProjectPinned(_ path: String) -> Bool {
        let normalized = normalizePath(path)
        return pinnedProjectPaths.contains(normalized)
    }

    // Legacy compatibility - pin by session ID (converts to project path)
    func pinSession(_ sessionId: String) {
        if let session = sessions[sessionId] {
            pinProjectPath(session.projectPath)
        }
    }

    func unpinSession(_ sessionId: String) {
        if let session = sessions[sessionId] {
            unpinProjectPath(session.projectPath)
        }
    }

    func unpinAllSessions() {
        unpinAllProjects()
    }

    // MARK: - Ralph Loop State Updates

    /// Update OpenCode Ralph state for all sessions matching a project path
    func updateOpenCodeRalphState(forProjectPath path: String, state: OpenCodeRalphState?) {
        let normalized = normalizePath(path)

        for (sessionId, session) in sessions {
            if session.normalizedPath == normalized {
                if sessions[sessionId]?.openCodeRalphState != state {
                    sessions[sessionId]?.openCodeRalphState = state
                }
            }
        }
    }

    /// Update Claude Code Ralph state for all sessions matching a project path
    func updateClaudeCodeRalphState(forProjectPath path: String, state: ClaudeCodeRalphState?) {
        let normalized = normalizePath(path)

        for (sessionId, session) in sessions {
            if session.normalizedPath == normalized {
                if sessions[sessionId]?.claudeCodeRalphState != state {
                    sessions[sessionId]?.claudeCodeRalphState = state
                }
            }
        }
    }

    /// Ensure a session exists for an OpenCode Ralph loop
    func ensureOpenCodeRalphSession(forProjectPath path: String, state: OpenCodeRalphState) {
        let normalized = normalizePath(path)
        let existingSession = sessions.values.first { $0.normalizedPath == normalized }

        if let existingSession = existingSession {
            if existingSession.openCodeRalphState != state {
                sessions[existingSession.id]?.openCodeRalphState = state
                sessions[existingSession.id]?.isActive = state.active
                sessions[existingSession.id]?.lastActivityTime = Date()
            }
        } else {
            let projectName = URL(fileURLWithPath: path).lastPathComponent
            let sessionId = "opencode-ralph-\(UUID().uuidString)"

            var session = SessionState(
                id: sessionId,
                projectPath: normalized,
                normalizedPath: normalized,
                projectName: projectName,
                permissionMode: "opencode-ralph",
                startTime: state.startDate ?? Date(),
                lastActivityTime: Date()
            )
            session.isActive = state.active
            session.openCodeRalphState = state

            sessions[sessionId] = session
        }

        // No auto-pin - user must explicitly use /send-to-notch
        isIdle = false
        lastActivityTime = Date()
    }

    /// Ensure a session exists for a Claude Code Ralph loop
    func ensureClaudeCodeRalphSession(forProjectPath path: String, state: ClaudeCodeRalphState) {
        let normalized = normalizePath(path)
        let existingSession = sessions.values.first { $0.normalizedPath == normalized }

        if let existingSession = existingSession {
            if existingSession.claudeCodeRalphState != state {
                sessions[existingSession.id]?.claudeCodeRalphState = state
                sessions[existingSession.id]?.isActive = state.isActive
                sessions[existingSession.id]?.lastActivityTime = Date()
            }
        } else {
            let projectName = URL(fileURLWithPath: path).lastPathComponent
            let sessionId = "claude-ralph-\(UUID().uuidString)"

            var session = SessionState(
                id: sessionId,
                projectPath: normalized,
                normalizedPath: normalized,
                projectName: projectName,
                permissionMode: "claude-ralph",
                startTime: state.timestampDate ?? Date(),
                lastActivityTime: Date()
            )
            session.isActive = state.isActive
            session.claudeCodeRalphState = state

            sessions[sessionId] = session
        }

        // No auto-pin - user must explicitly use /send-to-notch
        isIdle = false
        lastActivityTime = Date()
    }
}

// MARK: - AnyCodable (for flexible JSON parsing)

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unable to encode value"))
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case (let l as Bool, let r as Bool):
            return l == r
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as String, let r as String):
            return l == r
        case (let l as [Any], let r as [Any]):
            // Recursive array comparison
            guard l.count == r.count else { return false }
            for (lItem, rItem) in zip(l, r) {
                if AnyCodable(lItem) != AnyCodable(rItem) { return false }
            }
            return true
        case (let l as [String: Any], let r as [String: Any]):
            // Recursive dictionary comparison
            guard l.count == r.count else { return false }
            for (key, lValue) in l {
                guard let rValue = r[key] else { return false }
                if AnyCodable(lValue) != AnyCodable(rValue) { return false }
            }
            return true
        default:
            return false
        }
    }
}
