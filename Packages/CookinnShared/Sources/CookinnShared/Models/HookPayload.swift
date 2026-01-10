//
//  HookPayload.swift
//  CookinnShared
//
//  Core data models for Claude Code CLI hook events
//  Shared between macOS and iOS apps
//

import Foundation

// MARK: - Hook Event Payload (from unified hook)

public struct HookPayload: Codable, Sendable {
    public let event: String
    public let sessionId: String
    public let cwd: String?
    public let projectName: String?
    public let permissionMode: String?
    public let toolName: String?
    public let toolUseId: String?
    public let toolInput: [String: AnyCodable]?
    public let toolResponse: [String: AnyCodable]?
    public let source: String?
    public let reason: String?
    public let message: String?
    public let notificationType: String?
    public let prompt: String?
    public let stopHookActive: Bool?
    public let timestamp: String?
    public let usage: TokenUsage?
    public let contextTokens: Int?
    public let contextPercent: Double?

    public init(
        event: String,
        sessionId: String,
        cwd: String? = nil,
        projectName: String? = nil,
        permissionMode: String? = nil,
        toolName: String? = nil,
        toolUseId: String? = nil,
        toolInput: [String: AnyCodable]? = nil,
        toolResponse: [String: AnyCodable]? = nil,
        source: String? = nil,
        reason: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        prompt: String? = nil,
        stopHookActive: Bool? = nil,
        timestamp: String? = nil,
        usage: TokenUsage? = nil,
        contextTokens: Int? = nil,
        contextPercent: Double? = nil
    ) {
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.projectName = projectName
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.toolInput = toolInput
        self.toolResponse = toolResponse
        self.source = source
        self.reason = reason
        self.message = message
        self.notificationType = notificationType
        self.prompt = prompt
        self.stopHookActive = stopHookActive
        self.timestamp = timestamp
        self.usage = usage
        self.contextTokens = contextTokens
        self.contextPercent = contextPercent
    }
}

// MARK: - Token Usage (from Claude Code Stop event)

public struct TokenUsage: Codable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?

    public var totalTokens: Int {
        (inputTokens ?? 0) + (outputTokens ?? 0)
    }

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

// MARK: - AnyCodable (for flexible JSON parsing)

public struct AnyCodable: Codable, Equatable, Sendable {
    public let value: AnyCodableValue

    public init(_ value: Any) {
        self.value = AnyCodableValue(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = .null
        } else if let bool = try? container.decode(Bool.self) {
            self.value = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = .double(double)
        } else if let string = try? container.decode(String.self) {
            self.value = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = .array(array.map { $0.value })
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = .dictionary(dict.mapValues { $0.value })
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try value.encode(to: &container)
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        lhs.value == rhs.value
    }
}

// Sendable-safe value representation
public enum AnyCodableValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])

    public init(_ value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { AnyCodableValue($0) })
        case let dict as [String: Any]:
            self = .dictionary(dict.mapValues { AnyCodableValue($0) })
        default:
            self = .null
        }
    }

    public var asAny: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.asAny }
        case .dictionary(let v): return v.mapValues { $0.asAny }
        }
    }

    func encode(to container: inout SingleValueEncodingContainer) throws {
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v.map { AnyCodable($0.asAny) })
        case .dictionary(let v):
            try container.encode(v.mapValues { AnyCodable($0.asAny) })
        }
    }
}

// Convenience accessor for backwards compatibility
public extension AnyCodable {
    var unwrapped: Any {
        value.asAny
    }
}
