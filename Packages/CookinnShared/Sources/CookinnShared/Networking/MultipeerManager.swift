//
//  MultipeerManager.swift
//  CookinnShared
//
//  Multipeer Connectivity manager for real-time sync between Mac and iPhone
//

import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Multipeer Manager

@MainActor
public final class MultipeerManager: NSObject, ObservableObject {
    /// Service type for Bonjour discovery (max 15 chars, lowercase + hyphen only)
    public static let serviceType = "cookinn-notch"

    // MARK: - Published State

    @Published public private(set) var connectedPeers: [MCPeerID] = []
    @Published public private(set) var availablePeers: [MCPeerID] = []
    @Published public private(set) var isAdvertising: Bool = false
    @Published public private(set) var isBrowsing: Bool = false
    @Published public private(set) var connectionState: ConnectionState = .disconnected

    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(peerCount: Int)
    }

    // MARK: - Callbacks

    /// Called when a message is received from a peer
    public var onMessageReceived: (@Sendable (SyncMessage, MCPeerID) -> Void)?

    /// Called when a peer connects (useful for sending full sync)
    public var onPeerConnected: (@Sendable (MCPeerID) -> Void)?

    /// Called when a peer disconnects
    public var onPeerDisconnected: (@Sendable (MCPeerID) -> Void)?

    // MARK: - Role

    public enum Role: Sendable {
        case advertiser  // macOS - advertises and accepts connections
        case browser     // iOS - browses and initiates connections
    }

    public let role: Role
    public let deviceName: String

    // MARK: - Private Properties

    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // MARK: - Initialization

    public init(displayName: String, role: Role) {
        self.deviceName = displayName
        self.role = role
        self.myPeerID = MCPeerID(displayName: displayName)

        super.init()

        // Create session with encryption
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.session.delegate = self

        // Set up role-specific components
        switch role {
        case .advertiser:
            setupAdvertiser()
        case .browser:
            setupBrowser()
        }
    }

    // MARK: - Advertiser Setup (macOS)

    private func setupAdvertiser() {
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["version": "1.0", "platform": "macOS"],
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
    }

    /// Start advertising to nearby devices (macOS)
    public func startAdvertising() {
        guard role == .advertiser else { return }
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
    }

    /// Stop advertising
    public func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        isAdvertising = false
    }

    // MARK: - Browser Setup (iOS)

    private func setupBrowser() {
        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: Self.serviceType
        )
        browser?.delegate = self
    }

    /// Start browsing for nearby devices (iOS)
    public func startBrowsing() {
        guard role == .browser else { return }
        browser?.startBrowsingForPeers()
        isBrowsing = true
    }

    /// Stop browsing
    public func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        isBrowsing = false
        availablePeers.removeAll()
    }

    /// Invite a discovered peer to connect (iOS)
    public func invitePeer(_ peerID: MCPeerID) {
        guard role == .browser else { return }
        connectionState = .connecting
        browser?.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 30
        )
    }

    // MARK: - Messaging

    /// Broadcast a message to all connected peers
    public func broadcast(_ message: SyncMessage) {
        guard !connectedPeers.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: connectedPeers, with: .reliable)
        } catch {
            print("[MultipeerManager] Broadcast failed: \(error.localizedDescription)")
        }
    }

    /// Send a message to a specific peer
    public func send(_ message: SyncMessage, to peer: MCPeerID) {
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            print("[MultipeerManager] Send failed: \(error.localizedDescription)")
        }
    }

    /// Broadcast raw data (for efficiency when data is already encoded)
    public func broadcastRaw(_ data: Data, type: SyncMessageType) {
        guard !connectedPeers.isEmpty else { return }

        let message = SyncMessage(type: type, payload: data, sourceDevice: deviceName)
        broadcast(message)
    }

    // MARK: - Disconnect

    /// Disconnect from all peers
    public func disconnect() {
        session.disconnect()
        stopAdvertising()
        stopBrowsing()
        connectedPeers.removeAll()
        availablePeers.removeAll()
        connectionState = .disconnected
    }

    // MARK: - Helpers

    private func updateConnectionState() {
        if connectedPeers.isEmpty {
            connectionState = .disconnected
        } else {
            connectionState = .connected(peerCount: connectedPeers.count)
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    nonisolated public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
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
                connectionState = .connecting
            @unknown default:
                break
            }
            updateConnectionState()
        }
    }

    nonisolated public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(SyncMessage.self, from: data)
            Task { @MainActor in
                onMessageReceived?(message, peerID)
            }
        } catch {
            print("[MultipeerManager] Failed to decode message: \(error.localizedDescription)")
        }
    }

    // Required but unused delegate methods
    nonisolated public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from iOS devices
        // In a production app, you might want to show a confirmation dialog
        Task { @MainActor in
            print("[MultipeerManager] Received invitation from \(peerID.displayName)")
            invitationHandler(true, session)
        }
    }

    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("[MultipeerManager] Failed to start advertising: \(error.localizedDescription)")
            isAdvertising = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !availablePeers.contains(peerID) {
                availablePeers.append(peerID)
                print("[MultipeerManager] Found peer: \(peerID.displayName)")
            }
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            availablePeers.removeAll { $0 == peerID }
            print("[MultipeerManager] Lost peer: \(peerID.displayName)")
        }
    }

    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("[MultipeerManager] Failed to start browsing: \(error.localizedDescription)")
            isBrowsing = false
        }
    }
}
