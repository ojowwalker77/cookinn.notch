//
//  SyncMessage.swift
//  CookinnShared
//
//  Message types for Multipeer Connectivity sync between Mac and iPhone
//

import Foundation

// MARK: - Sync Message Types

public enum SyncMessageType: String, Codable, Sendable {
    case hookEvent      // Full HookPayload from Claude Code
    case sessionUpdate  // SessionState changes
    case fullSync       // Complete state snapshot on connect
    case ping           // Keep-alive
    case pong           // Keep-alive response
}

// MARK: - Sync Message

public struct SyncMessage: Codable, Sendable {
    public let type: SyncMessageType
    public let payload: Data
    public let timestamp: Date
    public let sourceDevice: String

    public init(type: SyncMessageType, payload: Data, sourceDevice: String = "") {
        self.type = type
        self.payload = payload
        self.timestamp = Date()
        self.sourceDevice = sourceDevice
    }

    // Convenience initializers for common message types

    public static func hookEvent(_ payload: HookPayload, from device: String = "") -> SyncMessage? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return SyncMessage(type: .hookEvent, payload: data, sourceDevice: device)
    }

    public static func sessionUpdate(_ session: SessionState, from device: String = "") -> SyncMessage? {
        guard let data = try? JSONEncoder().encode(session) else { return nil }
        return SyncMessage(type: .sessionUpdate, payload: data, sourceDevice: device)
    }

    public static func fullSync(_ snapshot: StateSnapshot, from device: String = "") -> SyncMessage? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return SyncMessage(type: .fullSync, payload: data, sourceDevice: device)
    }

    public static func ping(from device: String = "") -> SyncMessage {
        SyncMessage(type: .ping, payload: Data(), sourceDevice: device)
    }

    public static func pong(from device: String = "") -> SyncMessage {
        SyncMessage(type: .pong, payload: Data(), sourceDevice: device)
    }

    // Decode payload helpers

    public func decodeHookPayload() -> HookPayload? {
        guard type == .hookEvent else { return nil }
        return try? JSONDecoder().decode(HookPayload.self, from: payload)
    }

    public func decodeSessionUpdate() -> SessionState? {
        guard type == .sessionUpdate else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: payload)
    }

    public func decodeFullSync() -> StateSnapshot? {
        guard type == .fullSync else { return nil }
        return try? JSONDecoder().decode(StateSnapshot.self, from: payload)
    }
}

// MARK: - State Snapshot (for full sync on connection)

public struct StateSnapshot: Codable, Sendable {
    public let sessions: [SessionState]
    public let pinnedPaths: [String]
    public let activeSessionId: String?
    public let timestamp: Date

    public init(
        sessions: [SessionState],
        pinnedPaths: [String],
        activeSessionId: String?,
        timestamp: Date = Date()
    ) {
        self.sessions = sessions
        self.pinnedPaths = pinnedPaths
        self.activeSessionId = activeSessionId
        self.timestamp = timestamp
    }
}
