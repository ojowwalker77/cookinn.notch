//
//  SessionState.swift
//  CookinnShared
//
//  Session and tool state models shared between macOS and iOS
//

import Foundation
import SwiftUI

// MARK: - Tool Display Info

public struct ToolDisplayInfo: Sendable {
    public let name: String
    public let displayName: String
    public let detail: String
    public let icon: String
    public let color: ToolColor

    public enum ToolColor: String, Sendable, Codable {
        case cyan, green, yellow, orange, red, purple, blue, indigo, pink, teal, mint, gray

        public var swiftUIColor: Color {
            switch self {
            case .cyan: return .cyan
            case .green: return .green
            case .yellow: return .yellow
            case .orange: return .orange
            case .red: return .red
            case .purple: return .purple
            case .blue: return .blue
            case .indigo: return .indigo
            case .pink: return .pink
            case .teal: return .teal
            case .mint: return .mint
            case .gray: return .gray
            }
        }
    }

    public init(name: String, displayName: String, detail: String, icon: String, color: ToolColor) {
        self.name = name
        self.displayName = displayName
        self.detail = detail
        self.icon = icon
        self.color = color
    }
}

// MARK: - Tool Input

public struct ToolInput: Equatable, Sendable, Codable {
    public let filePath: String?
    public let command: String?
    public let pattern: String?
    public let content: String?
    public let query: String?
    public let url: String?
    public let prompt: String?
    public let description: String?

    public init(
        filePath: String? = nil,
        command: String? = nil,
        pattern: String? = nil,
        content: String? = nil,
        query: String? = nil,
        url: String? = nil,
        prompt: String? = nil,
        description: String? = nil
    ) {
        self.filePath = filePath
        self.command = command
        self.pattern = pattern
        self.content = content
        self.query = query
        self.url = url
        self.prompt = prompt
        self.description = description
    }

    public init(from dict: [String: AnyCodable]?) {
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

        self.filePath = (dict["file_path"]?.unwrapped as? String) ?? (dict["filePath"]?.unwrapped as? String)
        self.command = dict["command"]?.unwrapped as? String
        self.pattern = dict["pattern"]?.unwrapped as? String
        self.content = dict["content"]?.unwrapped as? String
        self.query = dict["query"]?.unwrapped as? String
        self.url = dict["url"]?.unwrapped as? String
        self.prompt = dict["prompt"]?.unwrapped as? String
        self.description = dict["description"]?.unwrapped as? String
    }

    public var displayDetail: String {
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
}

// MARK: - Tool Response

public struct ToolResponse: Equatable, Sendable, Codable {
    public let success: Bool?
    public let filePath: String?
    public let error: String?
    public let output: String?

    public init(success: Bool? = nil, filePath: String? = nil, error: String? = nil, output: String? = nil) {
        self.success = success
        self.filePath = filePath
        self.error = error
        self.output = output
    }

    public init(from dict: [String: AnyCodable]?) {
        guard let dict = dict else {
            self.success = nil
            self.filePath = nil
            self.error = nil
            self.output = nil
            return
        }

        self.success = dict["success"]?.unwrapped as? Bool
        self.filePath = dict["filePath"]?.unwrapped as? String
        self.error = dict["error"]?.unwrapped as? String
        self.output = dict["output"]?.unwrapped as? String
    }
}

// MARK: - Active Tool State

public struct ActiveTool: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let input: ToolInput
    public let startTime: Date
    public var endTime: Date?
    public var response: ToolResponse?

    // Display properties (set by platform-specific config resolution)
    public var displayName: String
    public var colorName: String
    public var pattern: String
    public var intensity: Int
    public var attention: String

    public var isComplete: Bool { endTime != nil }

    public var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }

    public var durationSeconds: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    public var color: Color {
        ToolDisplayInfo.ToolColor(rawValue: colorName)?.swiftUIColor ?? .gray
    }

    public init(
        id: String,
        name: String,
        input: ToolInput,
        startTime: Date,
        endTime: Date? = nil,
        response: ToolResponse? = nil,
        displayName: String? = nil,
        colorName: String = "gray",
        pattern: String = "breathe",
        intensity: Int = 2,
        attention: String = "ambient"
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.startTime = startTime
        self.endTime = endTime
        self.response = response
        self.displayName = displayName ?? name
        self.colorName = colorName
        self.pattern = pattern
        self.intensity = intensity
        self.attention = attention
    }

    public static func == (lhs: ActiveTool, rhs: ActiveTool) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime
    }
}

// MARK: - Session State

public struct SessionState: Identifiable, Equatable, Sendable, Codable, Hashable {
    public let id: String
    public let projectPath: String
    public let projectName: String
    public var permissionMode: String
    public var startTime: Date
    public var lastActivityTime: Date
    public var activeTool: ActiveTool?
    public var recentTools: [ActiveTool]
    public var isActive: Bool
    public var isWaitingForPermission: Bool

    // Token tracking
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalCacheCreationTokens: Int
    public var totalCacheReadTokens: Int

    // Context window tracking
    public var contextPercent: Double
    public var contextTokens: Int

    public var displayName: String {
        projectName.isEmpty ? "Claude Code" : projectName
    }

    public var statusText: String {
        if isWaitingForPermission {
            return "Waiting"
        }
        if let tool = activeTool {
            return tool.displayName
        }
        return isActive ? "Thinking" : "Idle"
    }

    public var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    public var tokenStats: TokenStats {
        TokenStats(
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cacheCreationTokens: totalCacheCreationTokens,
            cacheReadTokens: totalCacheReadTokens,
            sessionStart: startTime
        )
    }

    public init(
        id: String,
        projectPath: String,
        projectName: String,
        permissionMode: String = "default",
        startTime: Date = Date(),
        lastActivityTime: Date = Date(),
        activeTool: ActiveTool? = nil,
        recentTools: [ActiveTool] = [],
        isActive: Bool = false,
        isWaitingForPermission: Bool = false,
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0,
        totalCacheCreationTokens: Int = 0,
        totalCacheReadTokens: Int = 0,
        contextPercent: Double = 0,
        contextTokens: Int = 0
    ) {
        self.id = id
        self.projectPath = projectPath
        self.projectName = projectName
        self.permissionMode = permissionMode
        self.startTime = startTime
        self.lastActivityTime = lastActivityTime
        self.activeTool = activeTool
        self.recentTools = recentTools
        self.isActive = isActive
        self.isWaitingForPermission = isWaitingForPermission
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.totalCacheReadTokens = totalCacheReadTokens
        self.contextPercent = contextPercent
        self.contextTokens = contextTokens
    }

    public static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.id == rhs.id &&
        lhs.activeTool == rhs.activeTool &&
        lhs.isActive == rhs.isActive &&
        lhs.isWaitingForPermission == rhs.isWaitingForPermission &&
        lhs.lastActivityTime == rhs.lastActivityTime &&
        lhs.contextPercent == rhs.contextPercent
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Token Stats

public struct TokenStats: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    public let sessionStart: Date

    public static let contextWindowSize: Int = 200_000

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public var contextUsagePercent: Double {
        Double(inputTokens) / Double(Self.contextWindowSize) * 100.0
    }

    public var isContextWarning: Bool {
        contextUsagePercent >= 90.0
    }

    public var isContextCritical: Bool {
        contextUsagePercent >= 95.0
    }

    public var estimatedCostCents: Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * 3.0 * 100.0
        let outputCost = Double(outputTokens) / 1_000_000.0 * 15.0 * 100.0
        return inputCost + outputCost
    }

    public var formattedCost: String {
        if estimatedCostCents < 1 {
            return "<1c"
        } else if estimatedCostCents < 100 {
            return String(format: "%.0fc", estimatedCostCents)
        } else {
            return String(format: "$%.2f", estimatedCostCents / 100.0)
        }
    }

    public var formattedTokens: String {
        if totalTokens < 1000 {
            return "\(totalTokens)"
        } else if totalTokens < 1_000_000 {
            return String(format: "%.1fK", Double(totalTokens) / 1000.0)
        } else {
            return String(format: "%.2fM", Double(totalTokens) / 1_000_000.0)
        }
    }

    public var formattedContext: String {
        String(format: "%.0f%%", contextUsagePercent)
    }

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        sessionStart: Date
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.sessionStart = sessionStart
    }
}
