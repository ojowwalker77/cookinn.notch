//
//  SessionCardView.swift
//  cookinn.notch
//
//  Extracted SessionCard for isolated observation boundary
//  Only re-renders when its specific session changes
//

import SwiftUI
import Combine

struct SessionCardView: View {
    let sessionId: String?

    // Observe only this session via computed property
    private var session: SessionState? {
        guard let id = sessionId else { return nil }
        return NotchState.shared.sessions[id]
    }

    // macOS Sequoia style
    private let cornerRadius: CGFloat = 12

    // Fun verb rotation for long-running thinking
    @State private var currentFunVerb: String = "Thinking"
    @State private var verbColorPhase: Double = 0.0

    // Visibility tracking for timer optimization
    @State private var isVisible: Bool = false

    // Managed timer cancellables (to prevent leaks)
    @State private var verbTimerCancellable: AnyCancellable?
    @State private var colorTimerCancellable: AnyCancellable?

    // Fast pulse animation for waiting state
    @State private var waitingPulseScale: CGFloat = 1.0
    @State private var waitingPulseOpacity: Double = 1.0
    @State private var pulseTimerCancellable: AnyCancellable?

    private var isThinking: Bool {
        guard let session = session else { return false }
        return session.isActive && session.activeTool == nil && !session.isWaitingForPermission && !session.isWaitingForInput
    }

    private var isWaitingForPermission: Bool {
        session?.isWaitingForPermission ?? false
    }

    private var isWaitingForInput: Bool {
        session?.isWaitingForInput ?? false
    }

    private var activeColor: Color {
        if isWaitingForPermission {
            return .red  // Urgent attention - waiting for user permission
        }
        if isWaitingForInput {
            return .yellow  // Waiting for user input (idle prompt)
        }
        if session?.isCompacting == true {
            return .purple  // Context compaction
        }
        // Ralph loop colors: Orange for Claude Code, Purple for OpenCode
        if isInRalphLoop {
            return ralphColor
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

    /// Color for Ralph loops: Orange for Claude Code, Purple for OpenCode
    private var ralphColor: Color {
        switch session?.ralphSource {
        case "claude":
            return .orange  // Classic Claude Code color
        case "opencode":
            return .purple  // OpenCode color
        default:
            return .purple  // Default fallback
        }
    }

    private var contextPercent: Double {
        session?.contextPercent ?? 0
    }

    private var contextColor: Color {
        // Always use neutral color - no warning colors based on percentage
        return .white.opacity(0.5)
    }

    private var isInRalphLoop: Bool {
        session?.isInRalphLoop ?? false
    }

    private var ralphIterationDisplay: String? {
        session?.ralphIterationDisplay
    }

    var body: some View {
        HStack(spacing: 8) {
            // Agent type badge (e.g., "Plan", "Explore") - shown first
            if let agentType = session?.agentTypeDisplay {
                Text(agentType)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Team badge: active teammate count
            if let count = session?.activeTeammateCount, count > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 7))
                    Text("\(count)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.teal.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            // Ralph loop iteration (shown when in loop, before context percent)
            if isInRalphLoop, let iteration = ralphIterationDisplay {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ralphColor)
                    Text(iteration)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(ralphColor)
                }
            }

            // Cost display (v2.1.6+)
            if let cost = session?.formattedCost {
                Text(cost)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
            }

            // Context percentage (only show when > 0)
            if contextPercent > 0 {
                Text("\(Int(contextPercent))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(contextColor)
                    .frame(width: 28, alignment: .trailing)
            }

            // Show pulsing dot when waiting (permission or input), otherwise show activity indicator
            if isWaitingForPermission || isWaitingForInput {
                WaitingPulseIndicatorView(color: activeColor, isVisible: $isVisible)
                    .frame(width: 20, height: 14)
            } else {
                ActivityIndicatorView(
                    sessionId: sessionId,
                    isVisible: $isVisible
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
            ContextBorderView(percent: contextPercent, cornerRadius: cornerRadius, color: activeColor)
        )
        // Combined pulse modifier for GPU efficiency
        .modifier(PulseModifier(
            isActive: isWaitingForPermission || isWaitingForInput,
            scale: waitingPulseScale,
            opacity: waitingPulseOpacity
        ))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .drawingGroup()  // GPU optimization: rasterize entire card
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
            } else if session?.isWaitingForInput != true {
                stopPulseAnimation()
            }
        }
        .onChange(of: session?.isWaitingForInput) { _, isWaiting in
            if isWaiting == true {
                startPulseAnimation()
            } else if session?.isWaitingForPermission != true {
                stopPulseAnimation()
            }
        }
        .onAppear {
            isVisible = true
            // Initialize with a fun verb
            if isThinking {
                currentFunVerb = ConfigManager.shared.randomFunVerb(for: "thinking") ?? "Thinking"
            }
            startTimers()
            if isWaitingForPermission || isWaitingForInput {
                startPulseAnimation()
            }
        }
        .onDisappear {
            isVisible = false
            stopTimers()
            stopPulseAnimation()
        }
    }

    // MARK: - Pulse Animation

    private func startPulseAnimation() {
        guard isVisible, pulseTimerCancellable == nil else { return }
        // Timer slightly shorter than animation for smoother overlap
        pulseTimerCancellable = Timer.publish(every: 0.30, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.33)) {
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
        guard isVisible else { return }

        // Verb rotation timer (only when thinking)
        if verbTimerCancellable == nil {
            verbTimerCancellable = Timer.publish(every: 4.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    guard self.isVisible, self.isThinking else { return }
                    if let newVerb = ConfigManager.shared.randomFunVerb(for: "thinking"),
                       newVerb != currentFunVerb {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentFunVerb = newVerb
                        }
                    }
                }
        }

        // Color animation timer - 4Hz for shimmer (optimized CPU usage)
        if colorTimerCancellable == nil {
            colorTimerCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    guard self.isVisible else { return }
                    guard self.session?.isActive == true || self.session?.activeTool != nil else { return }
                    verbColorPhase += 0.1  // Step matched to 4Hz for smooth animation
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
        let needsTimers = (session?.isActive == true || session?.activeTool != nil) && isVisible
        if needsTimers && verbTimerCancellable == nil {
            startTimers()
        } else if !needsTimers && verbTimerCancellable != nil {
            stopTimers()
        }
    }

    /// Compute project name safely without force-unwrapping
    private func projectName(for session: SessionState?) -> String {
        guard let session = session else { return "" }
        return session.projectName.isEmpty ? "session" : session.projectName
    }

    @ViewBuilder
    private var statusTextView: some View {
        // Capture session state once to avoid race conditions with @Observable
        // (multiple reads of session?.activeTool could return different values if state mutates mid-render)
        let currentSession = session
        let project = projectName(for: currentSession)
        let (verb, color) = computeVerbAndColor(for: currentSession)

        HStack(spacing: 0) {
            if !project.isEmpty {
                Text("\(project) : ")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(.white)
            }

            // Verb with animated color
            Text(verb)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(color)
                .animation(.easeInOut(duration: 0.3), value: verb)
        }
        .lineLimit(1)
    }

    /// Compute verb and color together from a consistent session snapshot
    /// This prevents race conditions where session state changes between computing verb and color
    private func computeVerbAndColor(for session: SessionState?) -> (verb: String, color: Color) {
        guard let session = session else {
            return ("Idle", .gray)
        }

        // Waiting states get full attention
        if session.isWaitingForPermission {
            return ("Waiting", .red)
        }

        if session.isWaitingForInput {
            return ("Input", .yellow)
        }

        // Context compaction
        if session.isCompacting {
            let phase = sin(verbColorPhase * .pi * 2) * 0.5 + 0.5
            return ("Compacting", Color.purple.opacity(0.7 + phase * 0.3))
        }

        // Active tool - use tool's display name and color
        if let tool = session.activeTool {
            let baseColor = session.isInRalphLoop ? ralphColor : tool.color
            let phase = sin(verbColorPhase * .pi * 2) * 0.5 + 0.5
            return (tool.displayName, baseColor.opacity(0.7 + phase * 0.3))
        }

        // Thinking state
        if session.isActive {
            let verb = session.isInRalphLoop ? "Ralphing" : currentFunVerb
            let baseColor: Color
            if session.isInRalphLoop {
                baseColor = ralphColor
            } else {
                let thinkingInfo = ConfigManager.shared.resolveStateInfo(for: "thinking")
                baseColor = ConfigManager.shared.swiftUIColor(for: thinkingInfo.color)
            }
            let phase = sin(verbColorPhase * .pi * 2) * 0.5 + 0.5
            return (verb, baseColor.opacity(0.7 + phase * 0.3))
        }

        // Idle but in a Ralph loop (between iterations)
        if session.isInRalphLoop {
            let phase = sin(verbColorPhase * .pi * 2) * 0.5 + 0.5
            return ("Ralphing", ralphColor.opacity(0.7 + phase * 0.3))
        }

        return ("Idle", .gray)
    }
}

// MARK: - Pulse Modifier (combines scale + opacity for GPU efficiency)

struct PulseModifier: ViewModifier {
    let isActive: Bool
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? scale : 1.0)
            .opacity(isActive ? opacity : 1.0)
    }
}
