//
//  NotchView.swift
//  cookinn.notch
//
//  Pill UI that sits below the MacBook notch
//  Shows Claude Code activity: tool details + status
//

import SwiftUI
import AppKit
import Combine

struct NotchView: View {
    @ObservedObject var state = NotchState.shared
    let displayID: String

    // Get active sessions (up to 3) - ONLY shows pinned projects, deduplicated by path
    private var activeSessions: [SessionState] {
        // Only show sessions from pinned project paths
        let pinnedSessions = state.sessions.values.filter { state.isProjectPinned($0.projectPath) }

        // Deduplicate by normalized projectPath - keep only the most active/recent session per path
        // Using normalized paths ensures symlinks and different path representations are treated as same
        var sessionsByPath: [String: SessionState] = [:]
        for session in pinnedSessions {
            let normalizedPath = state.normalizePath(session.projectPath)
            if let existing = sessionsByPath[normalizedPath] {
                // Keep the more active/recent session
                let keepNew = Self.shouldPrefer(session, over: existing)
                if keepNew {
                    sessionsByPath[normalizedPath] = session
                }
            } else {
                sessionsByPath[normalizedPath] = session
            }
        }

        let sorted = sessionsByPath.values.sorted { s1, s2 in
            // Prioritize: has tool > is active > most recent
            Self.shouldPrefer(s1, over: s2)
        }
        return Array(sorted)
    }

    // Compare two sessions: returns true if s1 should be preferred over s2
    private static func shouldPrefer(_ s1: SessionState, over s2: SessionState) -> Bool {
        // Waiting for permission is highest priority
        if s1.isWaitingForPermission && !s2.isWaitingForPermission { return true }
        if s2.isWaitingForPermission && !s1.isWaitingForPermission { return false }
        // Then: has active tool
        if s1.activeTool != nil && s2.activeTool == nil { return true }
        if s2.activeTool != nil && s1.activeTool == nil { return false }
        // Then: is actively thinking
        if s1.isActive && !s2.isActive { return true }
        if s2.isActive && !s1.isActive { return false }
        // Then: most recent activity wins
        if s1.lastActivityTime != s2.lastActivityTime {
            return s1.lastActivityTime > s2.lastActivityTime
        }
        // Finally: session ID as deterministic tie-breaker
        return s1.id < s2.id
    }

    // Per-screen hover: only fade this screen's pills
    private var opacity: Double {
        state.hoveredDisplayIDs.contains(displayID) ? 0.05 : 1.0
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(activeSessions) { session in
                SessionCard(session: session)
            }

            if activeSessions.isEmpty {
                SessionCard(session: nil)
            }
        }
        .opacity(opacity)
        .animation(.easeOut(duration: 0.15), value: opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

// MARK: - Session Card (individual rounded rectangle)

struct SessionCard: View {
    let session: SessionState?

    // macOS Sequoia style
    private let cornerRadius: CGFloat = 12

    // Fun verb rotation for long-running thinking
    @State private var currentFunVerb: String = "Thinking"
    @State private var verbColorPhase: Double = 0.0

    // Managed timer cancellables (to prevent leaks)
    @State private var verbTimerCancellable: AnyCancellable?
    @State private var colorTimerCancellable: AnyCancellable?

    // Fast pulse animation for waiting state
    @State private var waitingPulseScale: CGFloat = 1.0
    @State private var waitingPulseOpacity: Double = 1.0
    @State private var pulseTimerCancellable: AnyCancellable?

    private var isThinking: Bool {
        guard let session = session else { return false }
        return session.isActive && session.activeTool == nil && !session.isWaitingForPermission
    }

    private var isWaitingForPermission: Bool {
        session?.isWaitingForPermission ?? false
    }

    private var activeColor: Color {
        if isWaitingForPermission {
            return .red  // Urgent attention - waiting for user
        }
        if let tool = session?.activeTool {
            return tool.color
        }
        if isThinking {
            // Get color from thinking state config (orange - matches Claude Code's terminal)
            let thinkingInfo = ConfigManager.shared.resolveStateInfo(for: "thinking")
            return ConfigManager.shared.swiftUIColor(for: thinkingInfo.color)
        }
        return .gray
    }

    private var contextPercent: Double {
        session?.contextPercent ?? 0
    }

    private var contextColor: Color {
        if contextPercent >= 95 { return .red }
        if contextPercent >= 90 { return .orange }
        if contextPercent >= 75 { return .yellow }
        return .white.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Context percentage (far left, only show when > 0)
            if contextPercent > 0 {
                Text("\(Int(contextPercent))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(contextColor)
                    .frame(width: 28, alignment: .trailing)
            }

            // Show pulsing dot when waiting, otherwise show activity indicator
            if isWaitingForPermission {
                WaitingPulseIndicator(color: activeColor)
                    .frame(width: 20, height: 14)
            } else {
                ActivityIndicator(
                    session: session,
                    tool: session?.activeTool
                )
                .frame(width: 20, height: 14)
            }

            // Subtle divider
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 18)

            // project : action (with animated verb color)
            statusTextView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            ))
        .overlay(
            ContextBorder(percent: contextPercent, cornerRadius: cornerRadius, color: activeColor)
        )
        // Fast pulse animation on the whole pill when waiting for permission
        .scaleEffect(isWaitingForPermission ? waitingPulseScale : 1.0)
        .opacity(isWaitingForPermission ? waitingPulseOpacity : 1.0)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onChange(of: session?.isActive) { _, isActive in
            // Reset verb when thinking starts
            if isActive == true && session?.activeTool == nil {
                currentFunVerb = ConfigManager.shared.randomFunVerb(for: "thinking") ?? "Thinking"
            }
            // Restart timers when activity state changes
            updateTimers()
        }
        .onChange(of: session?.activeTool?.id) { _, _ in
            updateTimers()
        }
        .onChange(of: session?.isWaitingForPermission) { _, isWaiting in
            if isWaiting == true {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
        }
        .onAppear {
            // Initialize with a fun verb
            if isThinking {
                currentFunVerb = ConfigManager.shared.randomFunVerb(for: "thinking") ?? "Thinking"
            }
            startTimers()
            if isWaitingForPermission {
                startPulseAnimation()
            }
        }
        .onDisappear {
            stopTimers()
            stopPulseAnimation()
        }
    }

    // MARK: - Pulse Animation

    private func startPulseAnimation() {
        guard pulseTimerCancellable == nil else { return }
        // Fast pulse: 200ms cycle
        pulseTimerCancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Alternate between normal and scaled/dimmed
                    if waitingPulseScale > 1.0 {
                        waitingPulseScale = 1.0
                        waitingPulseOpacity = 1.0
                    } else {
                        waitingPulseScale = 1.03
                        waitingPulseOpacity = 0.85
                    }
                }
            }
    }

    private func stopPulseAnimation() {
        pulseTimerCancellable?.cancel()
        pulseTimerCancellable = nil
        withAnimation(.easeOut(duration: 0.15)) {
            waitingPulseScale = 1.0
            waitingPulseOpacity = 1.0
        }
    }

    private func startTimers() {
        // Verb rotation timer (only when thinking)
        if verbTimerCancellable == nil {
            verbTimerCancellable = Timer.publish(every: 4.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    guard self.isThinking else { return }
                    if let newVerb = ConfigManager.shared.randomFunVerb(for: "thinking"),
                       newVerb != currentFunVerb {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentFunVerb = newVerb
                        }
                    }
                }
        }

        // Color animation timer
        if colorTimerCancellable == nil {
            colorTimerCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    guard self.session?.isActive == true || self.session?.activeTool != nil else { return }
                    verbColorPhase += 0.02
                    if verbColorPhase > 1.0 { verbColorPhase = 0.0 }
                }
        }
    }

    private func stopTimers() {
        verbTimerCancellable?.cancel()
        verbTimerCancellable = nil
        colorTimerCancellable?.cancel()
        colorTimerCancellable = nil
    }

    private func updateTimers() {
        // Start or stop timers based on current state
        let needsTimers = session?.isActive == true || session?.activeTool != nil
        if needsTimers && verbTimerCancellable == nil {
            startTimers()
        } else if !needsTimers && verbTimerCancellable != nil {
            stopTimers()
        }
    }

    @ViewBuilder
    private var statusTextView: some View {
        let project = session?.projectName.isEmpty == false ? session!.projectName : (session != nil ? "session" : "")
        let verb = currentVerb

        HStack(spacing: 0) {
            if !project.isEmpty {
                Text("\(project) : ")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.white)
            }

            // Verb with animated color
            Text(verb)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(verbColor)
                .animation(.easeInOut(duration: 0.3), value: verb)
        }
        .lineLimit(1)
    }

    private var currentVerb: String {
        guard let session = session else { return "Idle" }

        if session.isWaitingForPermission {
            return "Waiting"
        }

        if let tool = session.activeTool {
            return tool.displayName
        }

        if session.isActive {
            return currentFunVerb
        }

        return "Idle"
    }

    private var verbColor: Color {
        // Waiting state gets full red attention
        if session?.isWaitingForPermission == true {
            return activeColor  // Red for waiting
        }

        guard session?.isActive == true || session?.activeTool != nil else {
            return .gray
        }

        // Animate between white and the active color
        let baseColor = activeColor
        let phase = sin(verbColorPhase * .pi * 2) * 0.5 + 0.5  // 0 to 1 smooth wave

        // Interpolate opacity to create shimmer effect
        return baseColor.opacity(0.7 + phase * 0.3)
    }

    private var statusText: String {
        guard let session = session else { return "Idle" }

        let project = session.projectName.isEmpty ? "session" : session.projectName

        if let tool = session.activeTool {
            return "\(project) : \(tool.displayName)"
        }

        if session.isActive {
            return "\(project) : \(currentFunVerb)"
        }

        return "\(project) : Idle"
    }
}

// MARK: - Activity Indicator (v2.0 semantic patterns)

struct ActivityIndicator: View {
    let session: SessionState?
    let tool: ActiveTool?

    // Grid: 3x2 = 6 squares
    // Layout:  0 1 2
    //          3 4 5
    private let cols = 3
    private let rows = 2
    private var totalSquares: Int { cols * rows }

    @State private var litSquares: Set<Int> = []
    @State private var sequenceIndex: Int = 0
    @State private var breatheOpacity: Double = 0.3
    @State private var lastUpdate: Date = Date()

    // Managed timer cancellable (to prevent leaks)
    @State private var animationTimerCancellable: AnyCancellable?

    private let squareSize: CGFloat = 5
    private let spacing: CGFloat = 2

    // MARK: - Computed Properties

    private var shouldAnimate: Bool {
        if tool != nil { return true }
        return session?.isActive ?? false
    }

    private var patternName: String {
        if let tool = tool {
            return tool.pattern
        }
        if session?.isActive == true {
            // Get pattern from thinking state config (cogitate - fast and confident)
            let thinkingInfo = ConfigManager.shared.resolveStateInfo(for: "thinking")
            return thinkingInfo.pattern
        }
        return "dormant"  // Idle state
    }

    private var patternConfig: PatternConfig? {
        ConfigManager.shared.patternConfig(for: patternName)
    }

    private var activeColor: Color {
        if let tool = tool {
            return tool.color
        }
        if session?.isActive == true {
            // Thinking = orange (matches Claude Code's terminal)
            let thinkingInfo = ConfigManager.shared.resolveStateInfo(for: "thinking")
            return ConfigManager.shared.swiftUIColor(for: thinkingInfo.color)
        }
        return .gray
    }

    // MARK: - Body

    // Duration since current activity started (for evolution)
    private var activityDuration: TimeInterval {
        if let tool = tool {
            return Date().timeIntervalSince(tool.startTime)
        }
        if let session = session, session.isActive {
            return Date().timeIntervalSince(session.lastActivityTime)
        }
        return 0
    }

    // Effective interval with duration evolution applied
    private var effectiveInterval: TimeInterval {
        let baseInterval = patternConfig?.interval ?? 0.12
        let speedMult = ConfigManager.shared.durationSpeedMultiplier(seconds: activityDuration)
        // Invert: lower speedMult = slower animation = longer interval
        return baseInterval / speedMult
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        RoundedRectangle(cornerRadius: 1)
                            .fill(squareColor(for: index))
                            .frame(width: squareSize, height: squareSize)
                    }
                }
            }
        }
        .onChange(of: patternName) { _, _ in
            // Reset when pattern changes
            sequenceIndex = 0
            lastUpdate = Date()
        }
        .onChange(of: shouldAnimate) { _, newValue in
            if newValue {
                startAnimationTimer()
            } else {
                // Clear lit squares when stopping
                withAnimation(.easeOut(duration: 0.2)) {
                    litSquares.removeAll()
                }
            }
        }
        .onAppear {
            if shouldAnimate {
                startAnimationTimer()
            }
        }
        .onDisappear {
            stopAnimationTimer()
        }
    }

    private func startAnimationTimer() {
        guard animationTimerCancellable == nil else { return }
        animationTimerCancellable = Timer.publish(every: 0.04, on: .main, in: .common)
            .autoconnect()
            .sink { now in
                guard self.shouldAnimate else { return }
                guard now.timeIntervalSince(lastUpdate) >= effectiveInterval else { return }
                lastUpdate = now
                updatePattern()
            }
    }

    private func stopAnimationTimer() {
        animationTimerCancellable?.cancel()
        animationTimerCancellable = nil
    }

    // MARK: - Pattern Logic

    private func updatePattern() {
        guard let config = patternConfig else {
            // Fallback to random
            updateRandom(min: 2, max: 4)
            return
        }

        switch config.mode {
        case "sequence":
            updateSequence(config.sequence ?? [[]])

        case "random":
            let range = config.litRange ?? [2, 4]
            let min = range.count > 0 ? range[0] : 2
            let max = range.count > 1 ? range[1] : 4
            updateRandom(min: min, max: max)

        case "breathe":
            updateBreathe()

        case "static":
            if let seq = config.sequence, !seq.isEmpty {
                withAnimation(.easeInOut(duration: 0.3)) {
                    litSquares = Set(seq[0])
                }
            }

        default:
            updateRandom(min: 2, max: 4)
        }
    }

    private func updateSequence(_ sequence: [[Int]]) {
        guard !sequence.isEmpty else { return }

        let frame = sequence[sequenceIndex % sequence.count]
        withAnimation(.easeInOut(duration: 0.08)) {
            litSquares = Set(frame)
        }
        sequenceIndex += 1
    }

    private func updateRandom(min: Int, max: Int) {
        let count = Int.random(in: min...max)
        var newLit = Set<Int>()
        while newLit.count < count && newLit.count < totalSquares {
            newLit.insert(Int.random(in: 0..<totalSquares))
        }
        withAnimation(.easeInOut(duration: 0.06)) {
            litSquares = newLit
        }
    }

    private func updateBreathe() {
        // Breathe: all squares, opacity pulses
        withAnimation(.easeInOut(duration: 0.4)) {
            litSquares = Set(0..<totalSquares)
            // Oscillate opacity
            breatheOpacity = breatheOpacity > 0.6 ? 0.3 : 0.9
        }
    }

    // MARK: - Color

    private func squareColor(for index: Int) -> Color {
        let isLit = litSquares.contains(index)

        if !shouldAnimate {
            // Dormant: show corners dimly
            let isDormant = (index == 0 || index == 5)
            return isDormant ? activeColor.opacity(0.3) : Color.gray.opacity(0.15)
        }

        // For breathe mode, use breatheOpacity
        if patternConfig?.mode == "breathe" {
            return isLit ? activeColor.opacity(breatheOpacity) : activeColor.opacity(0.15)
        }

        // Normal lit/unlit
        return isLit ? activeColor.opacity(0.9) : activeColor.opacity(0.2)
    }
}

// MARK: - Context Border (progress indicator around pill)

struct ContextBorder: View {
    let percent: Double
    let cornerRadius: CGFloat
    let color: Color  // Same color as activity indicator

    var body: some View {
        // Use trim on the pill shape for smooth progress
        PillBorderPath(cornerRadius: cornerRadius)
            .trim(from: 0, to: min(percent / 100, 1.0))
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .animation(.easeInOut(duration: 0.3), value: percent)
    }
}

// Shape that traces the pill border (left side rounded, right side flat)
struct PillBorderPath: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let r = min(cornerRadius, rect.height / 2)
        let w = rect.width
        let h = rect.height

        // Start at top-left corner (top of the arc)
        path.move(to: CGPoint(x: r, y: 0))

        // Top edge (left to right)
        path.addLine(to: CGPoint(x: w, y: 0))

        // Right edge (top to bottom) - no corner radius
        path.addLine(to: CGPoint(x: w, y: h))

        // Bottom edge (right to left)
        path.addLine(to: CGPoint(x: r, y: h))

        // Bottom-left corner arc
        path.addArc(
            center: CGPoint(x: r, y: h - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge (bottom to top)
        path.addLine(to: CGPoint(x: 0, y: r))

        // Top-left corner arc
        path.addArc(
            center: CGPoint(x: r, y: r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        return path
    }
}

// MARK: - Waiting Pulse Indicator (replaces cube when waiting for permission)

struct WaitingPulseIndicator: View {
    let color: Color

    @State private var pulsePhase: Double = 0.0
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        // Simple pulsing circle that fills the 3x2 grid space
        Circle()
            .fill(color)
            .scaleEffect(0.6 + pulsePhase * 0.4)  // Scale between 0.6 and 1.0
            .opacity(0.5 + pulsePhase * 0.5)      // Opacity between 0.5 and 1.0
            .onAppear {
                startPulse()
            }
            .onDisappear {
                timerCancellable?.cancel()
                timerCancellable = nil
            }
    }

    private func startPulse() {
        guard timerCancellable == nil else { return }
        // Fast pulse: 150ms cycle for urgency
        timerCancellable = Timer.publish(every: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    // Alternate between 0 and 1
                    pulsePhase = pulsePhase > 0.5 ? 0.0 : 1.0
                }
            }
    }
}

// MARK: - Preview

#Preview("Session Cards") {
    NotchView(displayID: "display-preview")
        .frame(width: 260, height: 140)
        .background(Color.gray.opacity(0.3))
}
