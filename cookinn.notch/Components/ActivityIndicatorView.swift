//
//  ActivityIndicatorView.swift
//  cookinn.notch
//
//  Extracted ActivityIndicator with visibility-aware timer optimization
//  3x2 grid animation with semantic patterns
//

import SwiftUI
import Combine

struct ActivityIndicatorView: View {
    let sessionId: String?
    @Binding var isVisible: Bool

    // Observe only this session via computed property
    private var session: SessionState? {
        guard let id = sessionId else { return nil }
        return NotchState.shared.sessions[id]
    }

    private var tool: ActiveTool? {
        session?.activeTool
    }

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
            // Use loop pattern when in a Ralph loop
            if session?.isInRalphLoop == true {
                return "loop"
            }
            return tool.pattern
        }
        if session?.isActive == true {
            // Use loop pattern when in a Ralph loop
            if session?.isInRalphLoop == true {
                return "loop"
            }
            // Get pattern from thinking state config (cogitate - fast and confident)
            let thinkingInfo = ConfigManager.shared.resolveStateInfo(for: "thinking")
            return thinkingInfo.pattern
        }
        // Idle but in Ralph loop - still show loop pattern
        if session?.isInRalphLoop == true {
            return "loop"
        }
        return "dormant"  // Idle state
    }

    private var patternConfig: PatternConfig? {
        ConfigManager.shared.patternConfig(for: patternName)
    }

    private var activeColor: Color {
        // Ralph loop colors: Orange for Claude Code, Purple for OpenCode
        if session?.isInRalphLoop == true {
            switch session?.ralphSource {
            case "claude":
                return .orange
            case "opencode":
                return .purple
            default:
                return .purple
            }
        }
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
        .drawingGroup()  // GPU optimization: rasterize entire indicator
        .onChange(of: patternName) { oldValue, newValue in
            // Reset when pattern changes and restart timer with new interval
            sequenceIndex = 0
            lastUpdate = Date()
            if shouldAnimate && isVisible {
                stopAnimationTimer()
                startAnimationTimer()
            }
        }
        .onChange(of: shouldAnimate) { _, newValue in
            if newValue && isVisible {
                startAnimationTimer()
            } else {
                // Clear lit squares when stopping
                withAnimation(.easeOut(duration: 0.2)) {
                    litSquares.removeAll()
                }
                stopAnimationTimer()
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible && shouldAnimate {
                startAnimationTimer()
            } else if !visible {
                stopAnimationTimer()
            }
        }
        .onAppear {
            if shouldAnimate && isVisible {
                startAnimationTimer()
            }
        }
        .onDisappear {
            stopAnimationTimer()
        }
    }

    private func startAnimationTimer() {
        guard isVisible, animationTimerCancellable == nil else { return }
        // Use effectiveInterval directly - floor at 8Hz to reduce CPU
        let interval = max(0.125, effectiveInterval)  // Floor at 8Hz (was 12Hz)
        animationTimerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { now in
                guard self.isVisible, self.shouldAnimate else { return }
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
            // Fallback to random - this means pattern not found in config
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

// MARK: - Waiting Pulse Indicator (replaces cube when waiting for permission)

struct WaitingPulseIndicatorView: View {
    let color: Color
    @Binding var isVisible: Bool

    @State private var pulsePhase: Double = 0.0
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        // Simple pulsing circle that fills the 3x2 grid space
        Circle()
            .fill(color)
            .scaleEffect(0.6 + pulsePhase * 0.4)  // Scale between 0.6 and 1.0
            .opacity(0.5 + pulsePhase * 0.5)      // Opacity between 0.5 and 1.0
            .onChange(of: isVisible) { _, visible in
                if visible {
                    startPulse()
                } else {
                    stopPulse()
                }
            }
            .onAppear {
                if isVisible {
                    startPulse()
                }
            }
            .onDisappear {
                stopPulse()
            }
    }

    private func startPulse() {
        guard timerCancellable == nil else { return }
        // Timer slightly shorter than animation for smoother overlap
        timerCancellable = Timer.publish(every: 0.30, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.33)) {
                    // Alternate between 0 and 1
                    pulsePhase = pulsePhase > 0.5 ? 0.0 : 1.0
                }
            }
    }

    private func stopPulse() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}
