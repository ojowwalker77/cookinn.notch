//
//  ClaudeCodeManager.swift
//  cookinn.notch
//
//  HTTP server that receives Claude Code hook events
//  Single endpoint: POST /hook receives all events via HTTP hooks
//

import Foundation
import Network
import Combine
import SwiftUI

@MainActor
final class ClaudeCodeServer: ObservableObject {
    static let shared = ClaudeCodeServer()

    // MARK: - Published Properties

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Private Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16 = 27182
    private let queue = DispatchQueue(label: "com.cookinn.notch.server", qos: .userInteractive)

    // Stale state timer
    private var staleCheckTimer: Timer?
    private let staleCheckInterval: TimeInterval = 5.0

    // Rate limiting
    private var requestTimestamps: [Date] = []
    private let maxRequestsPerMinute = 100

    // MARK: - Initialization

    private init() {}

    // MARK: - Server Control

    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { state in
                Task { @MainActor [weak self] in
                    self?.handleListenerStateChange(state)
                }
            }
            listener?.newConnectionHandler = { connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }
            listener?.start(queue: queue)

            // Start stale state checker
            startStaleStateChecker()

        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        staleCheckTimer?.invalidate()
        staleCheckTimer = nil
        isRunning = false
        NotchState.shared.isServerRunning = false
    }

    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            NotchState.shared.isServerRunning = true
        case .failed(let error):
            lastError = error.localizedDescription
            isRunning = false
            NotchState.shared.isServerRunning = false
        case .cancelled:
            isRunning = false
            NotchState.shared.isServerRunning = false
        default:
            break
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.receiveData(from: connection)
                case .failed, .cancelled:
                    self?.connections.removeAll { $0 === connection }
                default:
                    break
                }
            }
        }
        connections.append(connection)
        connection.start(queue: queue)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            Task { @MainActor [weak self] in
                if let data = data, !data.isEmpty {
                    self?.processHTTPRequest(data, connection: connection)
                }

                if isComplete || error != nil {
                    connection.cancel()
                    self?.connections.removeAll { $0 === connection }
                }
            }
        }
    }

    // MARK: - Input Validation

    private func jsonEscape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
              .replacingOccurrences(of: "\n", with: "\\n")
              .replacingOccurrences(of: "\r", with: "\\r")
              .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func checkRateLimit() -> Bool {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        requestTimestamps = requestTimestamps.filter { $0 > oneMinuteAgo }
        if requestTimestamps.count >= maxRequestsPerMinute {
            return false
        }
        requestTimestamps.append(now)
        return true
    }

    // MARK: - HTTP Processing

    private func processHTTPRequest(_ data: Data, connection: NWConnection) {
        // Rate limiting
        guard checkRateLimit() else {
            sendResponse(connection: connection, status: 429, body: "{\"error\":\"Rate limit exceeded\"}")
            return
        }

        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid request\"}")
            return
        }

        // Parse HTTP request line
        let lines = request.components(separatedBy: "\r\n")

        // Validate Content-Length if present
        if let contentLengthLine = lines.first(where: { $0.lowercased().hasPrefix("content-length:") }) {
            let value = String(contentLengthLine.dropFirst(15)).trimmingCharacters(in: .whitespaces)
            if let length = Int(value), length > 65536 {
                sendResponse(connection: connection, status: 413, body: "{\"error\":\"Payload too large\"}")
                return
            }
        }
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid request\"}")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid request\"}")
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Find body (after empty line)
        var body: String?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines.dropFirst(emptyLineIndex + 1)
            body = bodyLines.joined(separator: "\r\n")
        }

        // Route requests (localhost only - no auth needed)
        switch (method, path) {
        case ("POST", "/hook"):
            handleHookEvent(body: body, connection: connection)

        case ("POST", "/pin"):
            handlePin(body: body, connection: connection)

        case ("POST", "/unpin"):
            handleUnpin(body: body, connection: connection)

        case ("GET", "/health"):
            sendResponse(connection: connection, status: 200, body: "{\"healthy\":true}")

        case ("GET", "/status"):
            let state = NotchState.shared
            let hasActivity = state.hasActivity
            let sessionCount = state.sessions.count
            let currentTool = jsonEscape(state.activeTool?.name ?? "none")
            sendResponse(connection: connection, status: 200, body: """
                {"running":true,"sessions":\(sessionCount),"hasActivity":\(hasActivity),"currentTool":"\(currentTool)"}
                """)

        case ("GET", "/pinned"):
            let pinned = Array(NotchState.shared.pinnedProjectPaths)
            let json = try? JSONSerialization.data(withJSONObject: ["pinned": pinned], options: [])
            let body = json.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"pinned\":[]}"
            sendResponse(connection: connection, status: 200, body: body)

        default:
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"Not found\"}")
        }
    }

    private func handleHookEvent(body: String?, connection: NWConnection) {
        guard let body = body,
              let data = body.data(using: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"No body\"}")
            return
        }

        do {
            let payload = try JSONDecoder().decode(NativeHookPayload.self, from: data)
            NotchState.shared.handleHookEvent(payload.toHookPayload())
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
        } catch {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid JSON payload\"}")
        }
    }

    private func handlePin(body: String?, connection: NWConnection) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Missing body\"}")
            return
        }

        // Pin by project path (cwd) - this persists across session restarts
        if let cwd = json["cwd"] as? String {
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent
            NotchState.shared.pinProjectPath(cwd)
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"pinned\":\"\(jsonEscape(cwd))\",\"project\":\"\(jsonEscape(projectName))\"}")
        } else if let sessionId = json["sessionId"] as? String {
            // Legacy: pin by session ID (converts to project path)
            NotchState.shared.pinSession(sessionId)
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"pinned\":\"\(jsonEscape(sessionId))\"}")
        } else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Missing sessionId or cwd\"}")
        }
    }

    private func handleUnpin(body: String?, connection: NWConnection) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Missing body\"}")
            return
        }

        if let cwd = json["cwd"] as? String {
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent
            NotchState.shared.unpinProjectPath(cwd)
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"unpinned\":\"\(jsonEscape(cwd))\",\"project\":\"\(jsonEscape(projectName))\"}")
        } else if let sessionId = json["sessionId"] as? String {
            // Legacy: unpin by session ID
            NotchState.shared.unpinSession(sessionId)
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"unpinned\":\"\(jsonEscape(sessionId))\"}")
        } else if json["all"] as? Bool == true {
            // Explicit request to unpin all
            NotchState.shared.unpinAllProjects()
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"unpinned\":\"all\"}")
        } else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Missing cwd, sessionId, or all parameter\"}")
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        case 429: statusText = "Too Many Requests"
        default: statusText = "Unknown"
        }

        let response = """
            HTTP/1.1 \(status) \(statusText)\r
            Content-Type: application/json\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { error in
            connection.cancel()
        })
    }

    // MARK: - Stale State Handling

    private func startStaleStateChecker() {
        staleCheckTimer?.invalidate()
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: staleCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                // Batch updates without animation to prevent jank (P1.5 optimization)
                withTransaction(Transaction(animation: nil)) {
                    NotchState.shared.clearStaleStates()
                    NotchState.shared.checkIdleState()
                }
                RalphLoopManager.shared.checkRalphLoops()  // Delegate to RalphLoopManager
            }
        }
    }
}
