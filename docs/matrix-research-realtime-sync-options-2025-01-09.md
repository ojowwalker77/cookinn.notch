> Report generated via **Claude Matrix - Deep Research Tool**
> [github.com/ojowwalker77/Claude-Matrix](https://github.com/ojowwalker77/Claude-Matrix)

---

# Research: Real-Time Live Sync Between macOS and iPhone Apps

## Summary

For live-syncing localhost webhook data from a macOS app to an iPhone companion with sub-second latency, there are **three tiers of solutions**: (1) **Local Network** options like Multipeer Connectivity and Network.framework work when devices are on the same WiFi/Bluetooth range with <100ms latency; (2) **Tunnel/Relay** solutions like Cloudflare Tunnel or ngrok expose localhost to the internet enabling remote sync; (3) **Cloud Pub/Sub** services like MQTT, Firebase, Supabase, or Ably provide managed real-time infrastructure with 50-200ms latency. For cookinn.notch, the recommended approach is a **hybrid**: Multipeer Connectivity for local/home use + MQTT or Cloudflare Tunnel for remote access.

---

## Key Findings

### 1. Multipeer Connectivity (Local Network - Best for Same-Room Use)

Apple's framework for peer-to-peer communication without internet. Uses WiFi, peer-to-peer WiFi, and Bluetooth automatically.

**Latency:** <50ms on same network
**Range:** Same room / WiFi network
**Effort:** Medium
**Internet Required:** No

**How It Works:**
- Built on top of Bonjour (mDNS) for discovery
- Automatic protocol selection (WiFi > peer-to-peer WiFi > Bluetooth)
- End-to-end encrypted with `.required` encryption preference

**Implementation:**
```swift
// Mac App - Advertiser
class NotchAdvertiser: NSObject, MCNearbyServiceAdvertiserDelegate {
    private let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var advertiser: MCNearbyServiceAdvertiser!
    private var session: MCSession!

    func start() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: "cookinn-notch"  // max 15 chars, lowercase + hyphens
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
    }

    func broadcast(_ event: HookPayload) {
        guard !session.connectedPeers.isEmpty else { return }
        let data = try! JSONEncoder().encode(event)
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// iPhone App - Browser
class NotchBrowser: NSObject, MCNearbyServiceBrowserDelegate {
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var browser: MCNearbyServiceBrowser!
    private var session: MCSession!

    func start() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "cookinn-notch")
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
}
```

**Pros:**
- Zero internet dependency
- Very low latency (<50ms)
- No server costs
- Works offline
- Apple-native, no third-party dependencies

**Cons:**
- Requires same network/proximity
- Can be flaky with Bluetooth
- Doesn't work remotely (coffee shop, office)
- Discovery can take 1-5 seconds

---

### 2. Apple Network.framework (Local Network - More Control)

Lower-level alternative to Multipeer for custom protocols over TCP/UDP with Bonjour discovery.

**Latency:** <30ms on same network
**Range:** Same WiFi network
**Effort:** Medium-High

**Server (Mac):**
```swift
import Network

class NotchServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    func start(port: UInt16 = 27183) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        listener = try! NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        // Advertise via Bonjour
        listener?.service = NWListener.Service(name: "CookinnNotch", type: "_cookinn._tcp")

        listener?.newConnectionHandler = { [weak self] connection in
            self?.connections.append(connection)
            connection.start(queue: .main)
        }

        listener?.start(queue: .main)
    }

    func broadcast(_ data: Data) {
        for conn in connections where conn.state == .ready {
            conn.send(content: data, completion: .contentProcessed { _ in })
        }
    }
}
```

**Client (iPhone):**
```swift
class NotchClient {
    private var connection: NWConnection?
    private var browser: NWBrowser?

    func discover() {
        browser = NWBrowser(for: .bonjour(type: "_cookinn._tcp", domain: nil), using: .tcp)
        browser?.browseResultsChangedHandler = { results, _ in
            if let result = results.first {
                self.connect(to: result.endpoint)
            }
        }
        browser?.start(queue: .main)
    }

    func connect(to endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.receiveMessage { data, _, _, _ in
            if let data = data {
                // Handle incoming hook event
            }
        }
        connection?.start(queue: .main)
    }
}
```

**Pros:**
- Even lower latency than Multipeer
- Custom framing/protocols (iOS 13+)
- More control over connection lifecycle
- Supports UDP for lowest latency

**Cons:**
- More code to write
- Same local-network limitation
- Need to handle reconnection manually

---

### 3. Cloudflare Tunnel (Remote Access - Free)

Exposes localhost to the internet via outbound-only connection. Free tier with unlimited bandwidth.

**Latency:** 100-300ms (depends on distance to edge)
**Range:** Worldwide
**Effort:** Low (setup) + Medium (integration)
**Cost:** Free

**How It Works:**
1. `cloudflared` daemon runs on Mac
2. Creates outbound tunnel to Cloudflare edge
3. iPhone connects to `https://yourapp.trycloudflare.com`
4. Traffic relayed back to localhost:27182

**Setup:**
```bash
# Install cloudflared
brew install cloudflared

# Quick tunnel (random subdomain, great for testing)
cloudflared tunnel --url http://localhost:27182

# Or named tunnel with custom domain
cloudflared tunnel create cookinn-notch
cloudflared tunnel route dns cookinn-notch notch.yourdomain.com
cloudflared tunnel run cookinn-notch
```

**Integration in cookinn.notch:**
```swift
// Mac App - Launch cloudflared as subprocess
class TunnelManager {
    private var process: Process?

    func start() {
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cloudflared")
        process?.arguments = ["tunnel", "--url", "http://localhost:27182"]

        let pipe = Pipe()
        process?.standardOutput = pipe

        // Parse tunnel URL from output
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let output = String(data: handle.availableData, encoding: .utf8) ?? ""
            if let range = output.range(of: "https://[^\\s]+\\.trycloudflare\\.com", options: .regularExpression) {
                let tunnelURL = String(output[range])
                // Share this URL with iPhone via iCloud KV Store
                NSUbiquitousKeyValueStore.default.set(tunnelURL, forKey: "tunnelURL")
            }
        }

        try? process?.run()
    }
}
```

**iPhone App - Connect via SSE or WebSocket:**
```swift
class RemoteNotchClient {
    func connect() {
        guard let urlString = NSUbiquitousKeyValueStore.default.string(forKey: "tunnelURL"),
              let url = URL(string: urlString + "/events") else { return }

        // Use SSE for streaming events
        let eventSource = EventSource(url: url)
        eventSource.onMessage { event in
            // Handle hook event
        }
    }
}
```

**Pros:**
- Works from anywhere in the world
- Free with unlimited bandwidth
- No firewall/port forwarding needed
- HTTPS by default
- Zero Trust authentication available

**Cons:**
- Requires Mac to be online
- Latency higher than local network
- Random URL changes on restart (unless named tunnel)
- Cloudflare dependency

---

### 4. ngrok (Remote Access - Freemium)

Similar to Cloudflare Tunnel but with more features and a paid tier.

**Latency:** 100-300ms
**Cost:** Free (limited) / $8+/mo (static domain)

```bash
# Quick start
ngrok http 27182

# With static domain (paid)
ngrok http --domain=cookinn.ngrok.io 27182
```

**Pros:**
- Easy setup
- Web inspection UI at localhost:4040
- Request replay for debugging

**Cons:**
- Free tier has connection limits
- Random URLs without paid plan
- $8/month for static domain

---

### 5. Tailscale (Private Mesh VPN)

Creates a private mesh network between your devices using WireGuard.

**Latency:** 50-150ms (peer-to-peer when possible)
**Range:** Worldwide
**Cost:** Free for personal use (up to 100 devices)

**How It Works:**
- Install Tailscale on Mac and iPhone
- Both devices get private IPs (100.x.x.x)
- Mac's localhost:27182 becomes accessible at 100.x.x.x:27182
- Direct peer-to-peer connection when possible

**Pros:**
- Zero config after setup
- Works from anywhere
- Direct P2P = lower latency than cloud relay
- Free for personal use
- Excellent iOS/macOS apps

**Cons:**
- Requires Tailscale app running on both devices
- VPN slot used (can't use with other VPNs on iOS)
- Not programmable (no Swift SDK)

---

### 6. MQTT with CocoaMQTT (Cloud Pub/Sub)

Lightweight pub/sub protocol designed for IoT with minimal overhead.

**Latency:** 50-150ms
**Effort:** Medium
**Cost:** Free (self-hosted) or $0-50/mo (managed)

**Architecture:**
```
[Mac: cookinn.notch] --publish--> [MQTT Broker] --subscribe--> [iPhone App]
          |                            |                            |
     localhost:27182              Cloud/Local                 Real-time UI
          |                       (HiveMQ/EMQX)
     Hook events
```

**Mac Publisher:**
```swift
import CocoaMQTT

class MQTTPublisher {
    private var mqtt: CocoaMQTT5!

    func connect() {
        mqtt = CocoaMQTT5(clientID: "cookinn-mac-\(UUID().uuidString)",
                         host: "broker.hivemq.com",  // Free public broker
                         port: 1883)
        mqtt.connect()
    }

    func publish(_ event: HookPayload) {
        let data = try! JSONEncoder().encode(event)
        let message = CocoaMQTT5Message(topic: "cookinn/\(userId)/events", payload: data)
        mqtt.publish(message)
    }
}
```

**iPhone Subscriber:**
```swift
class MQTTSubscriber: CocoaMQTT5Delegate {
    private var mqtt: CocoaMQTT5!

    func connect() {
        mqtt = CocoaMQTT5(clientID: "cookinn-iphone-\(UUID().uuidString)",
                         host: "broker.hivemq.com",
                         port: 1883)
        mqtt.delegate = self
        mqtt.connect()
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        mqtt.subscribe("cookinn/\(userId)/events")
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        let event = try! JSONDecoder().decode(HookPayload.self, from: message.payload)
        // Update UI
    }
}
```

**Broker Options:**
| Broker | Cost | Latency | Notes |
|--------|------|---------|-------|
| HiveMQ Cloud | Free tier | ~100ms | 100 connections free |
| EMQX Cloud | Free tier | ~80ms | 1M messages/mo free |
| Mosquitto (self-hosted) | Free | Varies | Run on VPS or home server |
| AWS IoT Core | Pay-per-use | ~50ms | Enterprise-grade |

**Pros:**
- Very low overhead (<3 bytes per message)
- Works anywhere with internet
- QoS levels for reliability
- Designed for real-time
- Many managed options with free tiers

**Cons:**
- Need external broker (or self-host)
- Slightly more complex than HTTP
- Security requires TLS setup

---

### 7. Firebase Realtime Database (Managed Cloud)

Google's managed real-time sync with native iOS/macOS SDKs.

**Latency:** 100-200ms
**Effort:** Low
**Cost:** Free tier (100 concurrent, 1GB storage)

```swift
import FirebaseDatabase

// Mac - Write events
func publishEvent(_ event: HookPayload) {
    let ref = Database.database().reference()
    ref.child("sessions/\(sessionId)/events").childByAutoId().setValue(event.dictionary)
}

// iPhone - Listen for events
func subscribe() {
    let ref = Database.database().reference()
    ref.child("sessions/\(sessionId)/events").observe(.childAdded) { snapshot in
        // New event received
    }
}
```

**Pros:**
- Firebase SDK handles everything
- Offline persistence built-in
- Works on iOS, macOS, watchOS, tvOS
- Free tier generous for personal use

**Cons:**
- Google dependency
- Latency higher than local solutions
- Data stored on Google servers

---

### 8. Supabase Realtime (PostgreSQL + WebSocket)

Open-source Firebase alternative with Postgres Changes feature.

**Latency:** 100-200ms
**Effort:** Low-Medium
**Cost:** Free tier (500MB, 2 projects)

```swift
import Supabase

let client = SupabaseClient(supabaseURL: URL(string: "https://xxx.supabase.co")!,
                            supabaseKey: "your-anon-key")

// Mac - Insert event
try await client.from("events").insert(event)

// iPhone - Subscribe to changes
let channel = client.channel("events")
let subscription = channel.onPostgresChange(
    event: .insert,
    schema: "public",
    table: "events"
) { payload in
    // Handle new event
}
await channel.subscribe()
```

**Pros:**
- Open source (can self-host)
- SQL database (query flexibility)
- Row-level security
- Good Swift SDK

**Cons:**
- Postgres Changes has scaling limits
- Slightly higher latency than MQTT
- Free tier limited

---

### 9. Server-Sent Events (SSE) with Relay

Unidirectional streaming over HTTP. Simple to implement.

**Libraries:**
- [mattt/EventSource](https://github.com/mattt/EventSource) - AsyncSequence support
- [Recouse/EventSource](https://github.com/Recouse/EventSource) - Swift concurrency
- [LaunchDarkly/swift-eventsource](https://github.com/launchdarkly/swift-eventsource) - Production-tested

```swift
// iPhone - Subscribe to SSE stream
import EventSource

let eventSource = EventSource(url: URL(string: "https://yourserver.com/events")!)

for await event in eventSource.events {
    switch event {
    case .message(let message):
        let hookEvent = try JSONDecoder().decode(HookPayload.self, from: message.data!)
        // Update UI
    case .open:
        print("Connected")
    case .closed:
        print("Disconnected")
    }
}
```

**Pros:**
- Simple HTTP (works everywhere)
- Built into browsers (debugging easy)
- Lower overhead than WebSocket for one-way data
- Auto-reconnection in most libraries

**Cons:**
- Unidirectional only
- Requires server (can use Cloudflare Tunnel + local)

---

### 10. Ably / Pusher (Managed Pub/Sub)

Enterprise-grade real-time messaging platforms.

| Feature | Ably | Pusher |
|---------|------|--------|
| **Latency** | <65ms global median | 100-200ms |
| **Uptime SLA** | 99.999% | 99.95% |
| **Free Tier** | 6M messages/mo | 200k messages/day |
| **Swift SDK** | Yes | Yes |

```swift
// Ably example
import Ably

let client = ARTRealtime(key: "your-api-key")
let channel = client.channels.get("cookinn-events")

// Publish (Mac)
channel.publish("hook", data: eventJSON)

// Subscribe (iPhone)
channel.subscribe("hook") { message in
    // Handle event
}
```

**Pros:**
- Battle-tested infrastructure
- Global edge network
- Guaranteed message ordering
- History/replay features

**Cons:**
- Cost at scale
- External dependency
- Overkill for personal project

---

## Comparison Matrix

| Solution | Latency | Range | Cost | Effort | Reliability | Best For |
|----------|---------|-------|------|--------|-------------|----------|
| **Multipeer Connectivity** | <50ms | Local | Free | Medium | Good | Home/office use |
| **Network.framework** | <30ms | Local | Free | High | Good | Custom protocols |
| **Cloudflare Tunnel** | 100-300ms | Global | Free | Low | Excellent | Remote access |
| **Tailscale** | 50-150ms | Global | Free | Low | Excellent | Always-on VPN |
| **MQTT (CocoaMQTT)** | 50-150ms | Global | Free-$50/mo | Medium | Good | IoT-style messaging |
| **Firebase Realtime** | 100-200ms | Global | Free tier | Low | Excellent | Quick setup |
| **Supabase Realtime** | 100-200ms | Global | Free tier | Low | Good | SQL + realtime |
| **SSE** | 100-200ms | Global | Server cost | Low | Good | Simple streaming |
| **Ably** | <65ms | Global | Free-$$/mo | Low | Excellent | Enterprise |

---

## Recommended Architecture for cookinn.notch

### Hybrid Approach: Local + Remote

```
                     ┌─────────────────────────────────────────┐
                     │            Mac (cookinn.notch)          │
                     │                                         │
                     │  Claude Code ──hook──> localhost:27182  │
                     │                            │            │
                     │         ┌──────────────────┼────────────┤
                     │         │                  │            │
                     │         ▼                  ▼            │
                     │  Multipeer Adv.    Cloudflare Tunnel    │
                     │    (local)           (remote)           │
                     └─────────┬──────────────────┬────────────┘
                               │                  │
            ┌──────────────────┘                  └─────────────────┐
            │ (Same WiFi)                              (Internet)   │
            ▼                                                       ▼
    ┌───────────────┐                                    ┌─────────────────┐
    │    iPhone     │                                    │     iPhone      │
    │ (Multipeer)   │                                    │ (SSE/WebSocket) │
    │   <50ms       │                                    │   100-300ms     │
    └───────────────┘                                    └─────────────────┘
```

### Implementation Steps

1. **Add Multipeer to Mac app** - Advertise when HTTP server starts
2. **Add Multipeer to iPhone app** - Browse and connect when on same network
3. **Add Cloudflare Tunnel option** - User can enable for remote access
4. **Share tunnel URL via iCloud KV** - iPhone discovers URL automatically
5. **Add SSE endpoint to Mac server** - `/events` endpoint for streaming
6. **iPhone auto-selects mode** - Multipeer if available, else tunnel

### Fallback Strategy

```swift
class NotchConnection {
    enum Mode {
        case multipeer  // <50ms, same network
        case tunnel     // 100-300ms, anywhere
        case none
    }

    var currentMode: Mode = .none

    func connect() async {
        // Try Multipeer first (fastest)
        if await tryMultipeer() {
            currentMode = .multipeer
            return
        }

        // Fall back to Cloudflare Tunnel
        if let tunnelURL = NSUbiquitousKeyValueStore.default.string(forKey: "tunnelURL"),
           await tryTunnel(url: tunnelURL) {
            currentMode = .tunnel
            return
        }

        currentMode = .none
    }
}
```

---

## Best Practices

1. **Prefer local when possible** - Multipeer/Network.framework for lowest latency
2. **Use iCloud KV for config** - Share tunnel URLs, preferences between devices
3. **Implement graceful fallback** - Local → Tunnel → Offline mode
4. **Cache last state** - iPhone should show last known state when disconnected
5. **Heartbeat/ping** - Detect stale connections quickly (every 10-30s)
6. **Compress payloads** - Hook events can be JSON-compressed for tunnel
7. **Rate limit updates** - Don't spam UI; batch rapid events (100ms debounce)

---

## Common Pitfalls

1. **Multipeer discovery delay** - Can take 1-5 seconds; show "Searching..." UI
2. **Cloudflare URL changes** - Use named tunnels or sync URL via iCloud
3. **iOS background limits** - App can't receive data when backgrounded long
4. **WiFi isolation** - Some networks block device-to-device traffic
5. **VPN conflicts** - Tailscale uses VPN slot; can't combine with other VPNs
6. **MQTT broker security** - Don't use public brokers for sensitive data
7. **Firebase write limits** - 100 writes/second per database

---

## Code Example: Complete Multipeer Integration

```swift
// Shared/MultipeerManager.swift
import MultipeerConnectivity

@Observable
class MultipeerManager: NSObject {
    private let serviceType = "cookinn-notch"
    private let myPeerID: MCPeerID
    private var session: MCSession!

    #if os(macOS)
    private var advertiser: MCNearbyServiceAdvertiser?
    #else
    private var browser: MCNearbyServiceBrowser?
    #endif

    var connectedPeers: [MCPeerID] = []
    var onEventReceived: ((HookPayload) -> Void)?

    override init() {
        #if os(macOS)
        myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        #else
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        #endif

        super.init()

        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    #if os(macOS)
    func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func broadcast(_ event: HookPayload) {
        guard !session.connectedPeers.isEmpty else { return }
        if let data = try? JSONEncoder().encode(event) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }
    #else
    func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    #endif
}

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let event = try? JSONDecoder().decode(HookPayload.self, from: data) {
            DispatchQueue.main.async {
                self.onEventReceived?(event)
            }
        }
    }

    // ... other required delegate methods
}
```

---

## Sources

1. [Multipeer Connectivity - Apple Developer Documentation](https://developer.apple.com/documentation/multipeerconnectivity)
2. [Building Peer-to-Peer Sessions - Create with Swift](https://www.createwithswift.com/building-peer-to-peer-sessions-sending-and-receiving-data-with-multipeer-connectivity/)
3. [Network.framework - Apple Developer](https://developer.apple.com/documentation/network)
4. [Building a Server-Client App with Network.framework](https://rderik.com/blog/building-a-server-client-aplication-using-apple-s-network-framework/)
5. [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
6. [ngrok Documentation](https://ngrok.com)
7. [Tailscale - What is Tailscale](https://tailscale.com/kb/1151/what-is-tailscale)
8. [CocoaMQTT - GitHub](https://github.com/emqx/CocoaMQTT)
9. [LiveConnect iOS - Halodoc Engineering](https://blogs.halodoc.io/liveconnect-ios/)
10. [Firebase Realtime Database - Apple Platforms](https://firebase.google.com/docs/database/ios/start)
11. [Supabase Swift SDK](https://github.com/supabase/supabase-swift)
12. [Supabase Realtime Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
13. [EventSource Swift - mattt](https://github.com/mattt/EventSource)
14. [swift-eventsource - LaunchDarkly](https://github.com/launchdarkly/swift-eventsource)
15. [Ably vs Pusher Comparison](https://ably.com/compare/ably-vs-pusher)
16. [CloudKit Subscriptions - Hacking with Swift](https://www.hackingwithswift.com/read/33/8/delivering-notifications-with-cloudkit-push-messages-ckquerysubscription)
17. [Introducing Network.framework - WWDC18](https://developer.apple.com/videos/play/wwdc2018/715/)
