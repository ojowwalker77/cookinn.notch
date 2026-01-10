//
//  ClaudeCodeModels.swift
//  cookinn.notch
//
//  Comprehensive models for Claude Code CLI hook events
//

import Foundation
import Combine
import SwiftUI

// MARK: - Hook Event Payload (from unified hook)

struct HookPayload: Codable {
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
    let prompt: String?
    let stopHookActive: Bool?
    let timestamp: String?

    // Token usage (from Stop events)
    let usage: TokenUsage?

    // Context window tracking (from transcript JSONL parsing)
    let contextTokens: Int?
    let contextPercent: Double?

    // Claude Code sends camelCase JSON keys
    enum CodingKeys: String, CodingKey {
        case event
        case sessionId
        case cwd
        case projectName
        case permissionMode
        case toolName
        case toolUseId
        case toolInput
        case toolResponse
        case source
        case reason
        case message
        case notificationType
        case prompt
        case stopHookActive
        case timestamp
        case usage
        case contextTokens
        case contextPercent
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

    var isComplete: Bool { endTime != nil }
    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }

    // v2.0 Config-driven properties (category-based)
    private var resolved: ResolvedToolInfo {
        ConfigManager.shared.resolveToolInfo(for: name)
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
        resolved.displayName
    }

    var pattern: String {
        resolved.pattern
    }

    var intensity: Int {
        resolved.intensity
    }

    var attention: String {
        resolved.attention
    }

    var color: Color {
        ConfigManager.shared.swiftUIColor(for: resolved.color)
    }

    private var toolColorEnum: ToolDisplayInfo.ToolColor {
        switch resolved.color.lowercased() {
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
    let raw: [String: AnyCodable]?

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
            self.raw = nil
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
        self.raw = dict
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
    let projectName: String     // extracted from cwd
    var permissionMode: String  // default, plan, acceptEdits, dontAsk, bypassPermissions
    var startTime: Date
    var lastActivityTime: Date
    var activeTool: ActiveTool?
    var recentTools: [ActiveTool] = []
    var isActive: Bool = false  // Only true when Claude is actively responding
    var isWaitingForPermission: Bool = false  // True when Claude needs user permission (e.g., Bash)

    // Token tracking
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCacheCreationTokens: Int = 0
    var totalCacheReadTokens: Int = 0

    // Context window tracking (from transcript JSONL - more accurate)
    var contextPercent: Double = 0.0
    var contextTokens: Int = 0

    var displayName: String {
        projectName.isEmpty ? "Claude Code" : projectName
    }

    var statusText: String {
        if isWaitingForPermission {
            return "Waiting"
        }
        if let tool = activeTool {
            return tool.displayName
        }
        return isActive ? "Thinking" : "Idle"
    }

    // Token stats
    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    var tokenStats: TokenStats {
        TokenStats(
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cacheCreationTokens: totalCacheCreationTokens,
            cacheReadTokens: totalCacheReadTokens,
            sessionStart: startTime
        )
    }

    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        // Compare all fields that affect UI display
        lhs.id == rhs.id &&
        lhs.activeTool == rhs.activeTool &&
        lhs.isActive == rhs.isActive &&
        lhs.isWaitingForPermission == rhs.isWaitingForPermission &&
        lhs.lastActivityTime == rhs.lastActivityTime &&
        lhs.contextPercent == rhs.contextPercent
    }
}

// MARK: - Token Stats (computed display values)

struct TokenStats {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let sessionStart: Date

    // Context window limit (Claude models)
    static let contextWindowSize: Int = 200_000

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    var contextUsagePercent: Double {
        Double(inputTokens) / Double(Self.contextWindowSize) * 100.0
    }

    var isContextWarning: Bool {
        contextUsagePercent >= 90.0
    }

    var isContextCritical: Bool {
        contextUsagePercent >= 95.0
    }

    // Estimated cost (Sonnet pricing: $3/$15 per 1M tokens)
    var estimatedCostCents: Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * 3.0 * 100.0
        let outputCost = Double(outputTokens) / 1_000_000.0 * 15.0 * 100.0
        return inputCost + outputCost
    }

    var formattedCost: String {
        if estimatedCostCents < 1 {
            return "<1¢"
        } else if estimatedCostCents < 100 {
            return String(format: "%.0f¢", estimatedCostCents)
        } else {
            return String(format: "$%.2f", estimatedCostCents / 100.0)
        }
    }

    var formattedTokens: String {
        if totalTokens < 1000 {
            return "\(totalTokens)"
        } else if totalTokens < 1_000_000 {
            return String(format: "%.1fK", Double(totalTokens) / 1000.0)
        } else {
            return String(format: "%.2fM", Double(totalTokens) / 1_000_000.0)
        }
    }

    var formattedContext: String {
        String(format: "%.0f%%", contextUsagePercent)
    }
}

// MARK: - App State (singleton observable)

@MainActor
final class NotchState: ObservableObject {
    static let shared = NotchState()

    // UserDefaults keys for persistence
    private static let pinnedPathsKey = "NotchPinnedProjectPaths"
    private static let showOnAllMonitorsKey = "NotchShowOnAllMonitors"
    private static let selectedDisplayIDKey = "NotchSelectedDisplayID"
    private static let alertSoundsEnabledKey = "NotchAlertSoundsEnabled"
    private var isLoadingSettings = false

    // Settings
    @Published var showOnAllMonitors: Bool = false {
        didSet {
            guard !isLoadingSettings else { return }
            UserDefaults.standard.set(showOnAllMonitors, forKey: Self.showOnAllMonitorsKey)
        }
    }

    @Published var alertSoundsEnabled: Bool = true {
        didSet {
            guard !isLoadingSettings else { return }
            UserDefaults.standard.set(alertSoundsEnabled, forKey: Self.alertSoundsEnabledKey)
        }
    }

    @Published var selectedDisplayID: UInt32? = nil {
        didSet {
            guard !isLoadingSettings else { return }
            if let id = selectedDisplayID {
                // Safe: UInt32 (max ~4.3B) always fits in Int64 on 64-bit Macs
                UserDefaults.standard.set(Int(id), forKey: Self.selectedDisplayIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedDisplayIDKey)
            }
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
    @Published var sessions: [String: SessionState] = [:]
    @Published var activeSessionId: String?
    @Published var isServerRunning: Bool = false
    @Published var hoveredDisplayIDs: Set<String> = []  // Per-screen hover state
    @Published var lastError: String?
    @Published var lastActivityTime: Date = Date()
    @Published var isIdle: Bool = true
    @Published var pinnedProjectPaths: Set<String> = [] {
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

    var currentTokenStats: TokenStats? {
        currentSession?.tokenStats
    }

    var isContextWarning: Bool {
        currentTokenStats?.isContextWarning ?? false
    }

    private init() {
        // Load persisted settings on startup
        loadSettings()
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

        isLoadingSettings = false
    }

    private func savePinnedPaths() {
        let array = Array(pinnedProjectPaths)
        UserDefaults.standard.set(array, forKey: Self.pinnedPathsKey)
    }


    // MARK: - State Updates

    func handleHookEvent(_ payload: HookPayload) {
        let sessionId = payload.sessionId
        let now = Date()

        // Update context window tracking on every event (from transcript JSONL parsing)
        if let pct = payload.contextPercent, pct > 0 {
            if var session = sessions[sessionId] {
                session.contextPercent = pct
                session.contextTokens = payload.contextTokens ?? 0
                sessions[sessionId] = session
            }
        }

        // Clear waiting state on ANY event except Notification (which sets it)
        // This ensures immediate dismissal when user responds/rejects
        if payload.event != "Notification" {
            if let session = sessions[sessionId], session.isWaitingForPermission {
                sessions[sessionId]?.isWaitingForPermission = false
                AudioManager.shared.stopWaitingAlerts()
            }
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

        default:
            break
        }
    }

    private func handleToolStart(_ payload: HookPayload, sessionId: String, now: Date) {
        ensureSession(payload, sessionId: sessionId, now: now)

        guard let toolName = payload.toolName, !toolName.isEmpty else { return }

        // Check if we were waiting (to stop alerts)
        let wasWaiting = sessions[sessionId]?.isWaitingForPermission ?? false

        let tool = ActiveTool(
            id: payload.toolUseId ?? UUID().uuidString,
            name: toolName,
            input: ToolInput(from: payload.toolInput),
            startTime: now
        )

        sessions[sessionId]?.activeTool = tool
        sessions[sessionId]?.isActive = true  // Claude is actively working
        sessions[sessionId]?.isWaitingForPermission = false  // Tool started, permission granted
        sessions[sessionId]?.lastActivityTime = now
        activeSessionId = sessionId

        // Stop alerts immediately when tool starts (permission was granted)
        if wasWaiting {
            AudioManager.shared.stopWaitingAlerts()
        }

        // Mark as active
        lastActivityTime = now
        isIdle = false
    }

    private func handleToolEnd(_ payload: HookPayload, sessionId: String, now: Date) {
        guard var session = sessions[sessionId] else { return }

        let endingToolId = payload.toolUseId

        if var tool = session.activeTool {
            // Only process if this is the currently displayed tool
            if tool.id == endingToolId {
                tool.endTime = now
                tool.response = ToolResponse(from: payload.toolResponse)

                // Add to recent tools
                session.recentTools.insert(tool, at: 0)
                if session.recentTools.count > 10 {
                    session.recentTools.removeLast()
                }

                // Only clear if this was the active tool
                session.activeTool = nil
            }
        }

        session.lastActivityTime = now
        sessions[sessionId] = session
    }

    private func handleStop(_ payload: HookPayload, sessionId: String, now: Date) {
        // Agent finished responding - this is THE signal to go idle
        if var session = sessions[sessionId] {
            let wasWaiting = session.isWaitingForPermission

            session.activeTool = nil
            session.isActive = false  // Stop hook = idle, no other scenario
            session.isWaitingForPermission = false  // Clear waiting on stop (user rejected or responded)
            session.lastActivityTime = now

            // Accumulate token usage
            if let usage = payload.usage {
                session.totalInputTokens += usage.inputTokens ?? 0
                session.totalOutputTokens += usage.outputTokens ?? 0
                session.totalCacheCreationTokens += usage.cacheCreationInputTokens ?? 0
                session.totalCacheReadTokens += usage.cacheReadInputTokens ?? 0
            }

            sessions[sessionId] = session

            // Stop alerts when session stops (user rejected or conversation ended)
            if wasWaiting {
                AudioManager.shared.stopWaitingAlerts()
            }
        }

        // Update global activity time to reset idle timer
        lastActivityTime = now
    }

    private func handleSessionStart(_ payload: HookPayload, sessionId: String, now: Date) {
        ensureSession(payload, sessionId: sessionId, now: now)
        activeSessionId = sessionId

        // Auto-pin on explicit SessionStart only
        // /send-to-notch is fallback for re-pinning after removal
        let cwd = payload.cwd ?? ""
        if !cwd.isEmpty {
            pinProjectPath(cwd)
        } else {
            // Edge case: SessionStart without cwd - log but don't fail
            // User can still manually pin via /send-to-notch
            print("[cookinn.notch] SessionStart without cwd for session \(sessionId) - manual pin required")
        }
    }

    private func handleSessionEnd(sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        if activeSessionId == sessionId {
            activeSessionId = sessions.keys.first
        }
    }

    private func handleNotification(_ payload: HookPayload, sessionId: String) {
        // Check for permission prompt notifications
        let notifType = payload.notificationType?.lowercased() ?? ""
        let isPermissionPrompt = notifType == "permission_prompt" ||
                                 notifType.contains("permission") ||
                                 payload.message?.lowercased().contains("permission") == true

        if isPermissionPrompt {
            if var session = sessions[sessionId] {
                // Only trigger if not already waiting (prevent repeated sounds)
                let wasWaiting = session.isWaitingForPermission
                session.isWaitingForPermission = true
                session.isActive = false  // Claude is blocked waiting
                sessions[sessionId] = session

                // Start escalating alerts only on transition to waiting
                if !wasWaiting {
                    AudioManager.shared.startWaitingAlerts()
                }
            }
        }
    }

    private func handleUserPrompt(_ payload: HookPayload, sessionId: String, now: Date) {
        ensureSession(payload, sessionId: sessionId, now: now)

        // Mark session as active when user submits a prompt
        if var session = sessions[sessionId] {
            let wasWaiting = session.isWaitingForPermission
            session.isActive = true
            session.isWaitingForPermission = false  // User responded, clear waiting state
            session.lastActivityTime = now
            sessions[sessionId] = session

            // Stop alerts immediately when user responds
            if wasWaiting {
                AudioManager.shared.stopWaitingAlerts()
            }
        }
        activeSessionId = sessionId

        // Mark as active
        lastActivityTime = now
        isIdle = false
    }

    private func ensureSession(_ payload: HookPayload, sessionId: String, now: Date) {
        if sessions[sessionId] == nil {
            let session = SessionState(
                id: sessionId,
                projectPath: payload.cwd ?? "",
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

    func clearStaleStates() {
        let now = Date()

        for (id, session) in sessions {
            let timeSinceActivity = now.timeIntervalSince(session.lastActivityTime)

            // Only clear stuck tools after timeout (e.g., tool started but never ended)
            // isActive is controlled exclusively by Stop hook - no timeout override
            if timeSinceActivity > activityTimeout {
                if sessions[id]?.activeTool != nil {
                    sessions[id]?.activeTool = nil
                }
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
    private func normalizePath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        // Resolve symlinks and standardize the path
        if let resolved = try? url.resolvingSymlinksInPath() {
            return resolved.path
        }
        return (path as NSString).standardizingPath
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
        default:
            return false
        }
    }
}
