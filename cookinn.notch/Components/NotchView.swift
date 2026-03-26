//
//  NotchView.swift
//  cookinn.notch
//
//  Pill UI that sits below the MacBook notch
//  Shows Claude Code activity: tool details + status
//
//  Performance optimized: uses extracted subviews for isolated observation boundaries

import SwiftUI
import AppKit
import Combine

struct NotchView: View {
    var state = NotchState.shared
    let displayID: String

    // Get active sessions (up to 3) - ONLY shows pinned projects, deduplicated by path
    // Excludes sessions that have plans (shown as plan pills instead)
    private var activeSessions: [SessionState] {
        // Only show sessions from pinned project paths
        let pinnedSessions = state.sessions.values.filter { session in
            state.isProjectPinned(session.projectPath)
        }

        // Deduplicate by normalized projectPath - keep only the most active/recent session per path
        // Using cached normalizedPath avoids repeated symlink resolution
        var sessionsByPath: [String: SessionState] = [:]
        for session in pinnedSessions {
            if let existing = sessionsByPath[session.normalizedPath] {
                // Keep the more active/recent session
                let keepNew = Self.shouldPrefer(session, over: existing)
                if keepNew {
                    sessionsByPath[session.normalizedPath] = session
                }
            } else {
                sessionsByPath[session.normalizedPath] = session
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
            // Session cards - FADE on hover (not clickable)
            Group {
                ForEach(activeSessions) { session in
                    SessionCardView(sessionId: session.id)
                }

                if activeSessions.isEmpty {
                    SessionCardView(sessionId: nil)
                }
            }
            .allowsHitTesting(false)
            .opacity(opacity)
            .animation(.easeOut(duration: 0.15), value: opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

// MARK: - Legacy Compatibility Wrappers

/// Wrapper for backward compatibility - forwards to SessionCardView
struct SessionCard: View {
    let session: SessionState?

    var body: some View {
        SessionCardView(sessionId: session?.id)
    }
}

/// Wrapper for backward compatibility - forwards to ActivityIndicatorView
struct ActivityIndicator: View {
    let session: SessionState?
    let tool: ActiveTool?

    @State private var isVisible = true

    var body: some View {
        ActivityIndicatorView(sessionId: session?.id, isVisible: $isVisible)
    }
}

/// Wrapper for backward compatibility - forwards to ContextBorderView
struct ContextBorder: View {
    let percent: Double
    let cornerRadius: CGFloat
    let color: Color

    var body: some View {
        ContextBorderView(percent: percent, cornerRadius: cornerRadius, color: color)
    }
}

/// Wrapper for backward compatibility - forwards to WaitingPulseIndicatorView
struct WaitingPulseIndicator: View {
    let color: Color

    @State private var isVisible = true

    var body: some View {
        WaitingPulseIndicatorView(color: color, isVisible: $isVisible)
    }
}

// MARK: - Interactive Hosting View (custom hit-testing for click-through)

class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    /// Regions that should receive mouse events (in window coordinates)
    var hitTestRegions: [CGRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Check if point is in any interactive region
        for region in hitTestRegions {
            if region.contains(point) {
                return super.hitTest(point)
            }
        }
        // Click-through everywhere else
        return nil
    }
}

// MARK: - Preview

#Preview("Session Cards") {
    NotchView(displayID: "display-preview")
        .frame(width: 260, height: 140)
        .background(Color.gray.opacity(0.3))
}
