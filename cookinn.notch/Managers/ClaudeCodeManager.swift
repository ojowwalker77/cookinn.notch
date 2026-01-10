//
//  ClaudeCodeManager.swift
//  cookinn.notch
//
//  HTTP server that receives Claude Code hook events
//  Single endpoint: POST /hook receives all events from the unified hook script
//

import Foundation
import Network
import Combine
import MultipeerConnectivity
// Note: CookinnShared package must be added to Xcode project
// For now, we use MultipeerConnectivity directly with raw JSON data

@MainActor
final class ClaudeCodeServer: ObservableObject {
    static let shared = ClaudeCodeServer()

    // MARK: - Published Properties

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var connectedPeerCount: Int = 0

    // MARK: - Private Properties

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16 = 27182
    private let queue = DispatchQueue(label: "com.cookinn.notch.server", qos: .userInteractive)

    // Stale state timer
    private var staleCheckTimer: Timer?
    private let staleCheckInterval: TimeInterval = 5.0

    // Multipeer for iOS sync
    private(set) var multipeerManager: NotchMultipeerManager?

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

            // Start Multipeer advertising for iOS sync
            startMultipeerAdvertising()

        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Multipeer Advertising

    private func startMultipeerAdvertising() {
        #if os(macOS)
        let hostName = Host.current().localizedName ?? "Mac"
        multipeerManager = NotchMultipeerManager(displayName: hostName)
        multipeerManager?.onPeerConnected = { [weak self] peer in
            Task { @MainActor in
                self?.connectedPeerCount = self?.multipeerManager?.connectedPeers.count ?? 0
                print("[cookinn.notch] iOS device connected: \(peer.displayName)")
                self?.sendFullStateSync(to: peer)
            }
        }
        multipeerManager?.onPeerDisconnected = { [weak self] _ in
            Task { @MainActor in
                self?.connectedPeerCount = self?.multipeerManager?.connectedPeers.count ?? 0
            }
        }
        multipeerManager?.startAdvertising()
        print("[cookinn.notch] Started Multipeer advertising as '\(hostName)'")
        #endif
    }

    private func sendFullStateSync(to peer: MCPeerID) {
        // Send current sessions as JSON
        let sessionsArray = NotchState.shared.sessions.values.map { session -> [String: Any] in
            var dict: [String: Any] = [
                "id": session.id,
                "projectPath": session.projectPath,
                "projectName": session.projectName,
                "isActive": session.isActive,
                "isWaitingForPermission": session.isWaitingForPermission,
                "contextPercent": session.contextPercent
            ]
            if let tool = session.activeTool {
                dict["activeTool"] = [
                    "id": tool.id,
                    "name": tool.name,
                    "displayName": tool.displayName
                ]
            }
            return dict
        }

        let syncData: [String: Any] = [
            "type": "fullSync",
            "sessions": sessionsArray,
            "pinnedPaths": Array(NotchState.shared.pinnedProjectPaths),
            "activeSessionId": NotchState.shared.activeSessionId ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let data = try? JSONSerialization.data(withJSONObject: syncData) {
            multipeerManager?.send(data, to: peer)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        staleCheckTimer?.invalidate()
        staleCheckTimer = nil

        // Stop Multipeer advertising
        multipeerManager?.disconnect()
        multipeerManager = nil
        connectedPeerCount = 0

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

    // MARK: - HTTP Processing

    private func processHTTPRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid request\"}")
            return
        }

        // Parse HTTP request line
        let lines = request.components(separatedBy: "\r\n")
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

        // Find body (after empty line)
        var body: String?
        if let emptyLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines.dropFirst(emptyLineIndex + 1)
            body = bodyLines.joined(separator: "\r\n")
        }

        // Route requests
        switch (method, path) {
        case ("POST", "/hook"):
            handleHookEvent(body: body, connection: connection)

        case ("GET", "/health"):
            sendResponse(connection: connection, status: 200, body: "{\"healthy\":true}")

        case ("GET", "/status"):
            let state = NotchState.shared
            let hasActivity = state.hasActivity
            let sessionCount = state.sessions.count
            let currentTool = state.activeTool?.name ?? "none"
            sendResponse(connection: connection, status: 200, body: """
                {"running":true,"sessions":\(sessionCount),"hasActivity":\(hasActivity),"currentTool":"\(currentTool)"}
                """)

        case ("POST", "/pin"):
            handlePin(body: body, connection: connection)

        case ("POST", "/unpin"):
            handleUnpin(body: body, connection: connection)

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
            let payload = try JSONDecoder().decode(HookPayload.self, from: data)

            // Process the event locally
            NotchState.shared.handleHookEvent(payload)

            // Broadcast to connected iOS devices
            if let multipeer = multipeerManager, !multipeer.connectedPeers.isEmpty {
                // Wrap in message envelope and broadcast
                let envelope: [String: Any] = [
                    "type": "hookEvent",
                    "payload": body,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
                if let envelopeData = try? JSONSerialization.data(withJSONObject: envelope) {
                    multipeer.broadcast(envelopeData)
                }
            }

            sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")

        } catch {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"Invalid JSON: \(error.localizedDescription)\"}")
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
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"pinned\":\"\(cwd)\",\"project\":\"\(projectName)\"}")
        } else if let sessionId = json["sessionId"] as? String {
            // Legacy: pin by session ID (converts to project path)
            NotchState.shared.pinSession(sessionId)
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"pinned\":\"\(sessionId)\"}")
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
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"unpinned\":\"\(cwd)\",\"project\":\"\(projectName)\"}")
        } else if let sessionId = json["sessionId"] as? String {
            // Legacy: unpin by session ID
            NotchState.shared.unpinSession(sessionId)
            sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"unpinned\":\"\(sessionId)\"}")
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

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Stale State Handling

    private func startStaleStateChecker() {
        staleCheckTimer?.invalidate()
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: staleCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                NotchState.shared.clearStaleStates()
                NotchState.shared.checkIdleState()
            }
        }
    }
}

// MARK: - Multipeer Manager for iOS Sync

/// Simple Multipeer Connectivity manager for advertising to iOS devices
@MainActor
final class NotchMultipeerManager: NSObject, ObservableObject {
    static let serviceType = "cookinn-notch"  // Max 15 chars, lowercase + hyphen

    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var isAdvertising: Bool = false

    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?

    init(displayName: String) {
        self.myPeerID = MCPeerID(displayName: displayName)
        super.init()

        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.session.delegate = self

        self.advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["version": "1.0", "platform": "macOS"],
            serviceType: Self.serviceType
        )
        self.advertiser?.delegate = self
    }

    func startAdvertising() {
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        isAdvertising = false
    }

    func broadcast(_ data: Data) {
        guard !connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: connectedPeers, with: .reliable)
        } catch {
            print("[NotchMultipeer] Broadcast failed: \(error.localizedDescription)")
        }
    }

    func send(_ data: Data, to peer: MCPeerID) {
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("[NotchMultipeer] Send failed: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        session.disconnect()
        stopAdvertising()
        connectedPeers.removeAll()
    }
}

extension NotchMultipeerManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                    onPeerConnected?(peerID)
                }
            case .notConnected:
                if let index = connectedPeers.firstIndex(of: peerID) {
                    connectedPeers.remove(at: index)
                    onPeerDisconnected?(peerID)
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Mac doesn't need to receive data from iOS for now
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NotchMultipeerManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            print("[NotchMultipeer] Accepting invitation from \(peerID.displayName)")
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("[NotchMultipeer] Failed to start advertising: \(error.localizedDescription)")
            isAdvertising = false
        }
    }
}
