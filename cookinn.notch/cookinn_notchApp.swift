//
//  cookinn_notchApp.swift
//  cookinn.notch
//
//  Premium notch app that wraps around the MacBook notch
//  Shows Claude Code activity in real-time
//

import SwiftUI
import AppKit
import Combine

@main
struct cookinn_notchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Multiple windows - one per screen
    var notchWindows: [String: NSWindow] = [:]  // Key: screen displayID
    var statusItem: NSStatusItem?
    var onboardingWindow: NSWindow?
    private var hasCheckedSetup = false
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitor: Any?
    private var screenObserver: Any?

    // Notch dimensions (measured from screen)
    private var notchWidth: CGFloat = 180
    private var notchHeight: CGFloat = 32

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load config first
        _ = ConfigManager.shared

        // Check setup status and show onboarding if needed
        Task { @MainActor in
            await checkAndShowOnboarding()
        }

        // Continue with normal setup
        measureNotch()
        setupStatusBar()
        setupNotchWindows()
        setupObservers()
        setupScreenObserver()
        startServer()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func measureNotch() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            return
        }

        // Get notch width from auxiliary areas
        if let topLeftArea = screen.auxiliaryTopLeftArea,
           let topRightArea = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - topLeftArea.width - topRightArea.width + 4
        }

        // Get notch height from safe area
        if screen.safeAreaInsets.top > 0 {
            notchHeight = screen.safeAreaInsets.top
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "cookinn.notch")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Notch", action: #selector(showNotch), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Hide Notch", action: #selector(hideNotch), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Focus Active", action: #selector(focusActiveSession), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Clear All", action: #selector(clearAllPinned), keyEquivalent: "k"))
        menu.addItem(NSMenuItem.separator())

        // Settings
        let allMonitorsItem = NSMenuItem(title: "Show on All Monitors", action: #selector(toggleAllMonitors), keyEquivalent: "m")
        allMonitorsItem.tag = 101
        allMonitorsItem.state = NotchState.shared.showOnAllMonitors ? .on : .off
        menu.addItem(allMonitorsItem)

        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Status: Starting...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem(title: "Setup...", action: #selector(showSetup), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem?.menu = menu

        // Update status periodically
        updateStatusMenuItem()
    }

    private func updateStatusMenuItem() {
        guard let menu = statusItem?.menu,
              let statusMenuItem = menu.item(withTag: 100) else { return }

        let state = NotchState.shared
        let server = ClaudeCodeServer.shared

        var parts: [String] = []

        if server.isRunning {
            parts.append("Server: :27182")
        } else {
            parts.append("Server: Off")
        }

        if state.sessions.count > 0 {
            parts.append("Sessions: \(state.sessions.count)")
        }

        if let tool = state.activeTool {
            parts.append("Tool: \(tool.displayName)")
        }

        statusMenuItem.title = parts.joined(separator: " | ")

        // Schedule next update
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.updateStatusMenuItem()
        }
    }

    // MARK: - Multi-Display Support

    private func screenID(for screen: NSScreen) -> String {
        // Get unique display ID from screen
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "display-unknown"
    }

    private func setupNotchWindows() {
        // Remove old windows
        notchWindows.values.forEach { $0.orderOut(nil) }
        notchWindows.removeAll()

        // Determine which screens to use
        let screens: [NSScreen]
        if NotchState.shared.showOnAllMonitors {
            screens = NSScreen.screens
        } else {
            // Just main screen
            screens = NSScreen.main.map { [$0] } ?? []
        }

        for screen in screens {
            createWindowForScreen(screen)
        }

        // Set up mouse tracking for all windows
        setupMouseTracking()
    }

    private func createWindowForScreen(_ screen: NSScreen) {
        let screenFrame = screen.frame
        let displayID = screenID(for: screen)

        // Window dimensions - right side, stacked sessions
        let windowWidth: CGFloat = 260
        let sessionHeight: CGFloat = 42
        let maxSessions: CGFloat = 10  // Allow up to 10 sessions
        let windowHeight: CGFloat = sessionHeight * maxSessions + 12  // padding

        // Create window at origin (0,0) first
        let rect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hasShadow = false
        window.ignoresMouseEvents = true  // Click-through

        // Position at TOP-RIGHT of this screen, below menu bar
        let menuBarHeight = screenFrame.maxY - screen.visibleFrame.maxY
        let paddingX: CGFloat = 0
        let paddingY: CGFloat = 0
        window.setFrameOrigin(NSPoint(
            x: screenFrame.maxX - window.frame.width - paddingX,
            y: screenFrame.maxY - menuBarHeight - window.frame.height - paddingY
        ))

        let contentView = NotchView()
        window.contentView = NSHostingView(rootView: contentView)

        // Initially hidden
        window.orderOut(nil)

        notchWindows[displayID] = window
    }

    private func setupScreenObserver() {
        // Watch for screen configuration changes (displays added/removed)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupNotchWindows()
        }

        // Also watch for the setting change
        NotchState.shared.$showOnAllMonitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupNotchWindows()
            }
            .store(in: &cancellables)
    }

    private func setupMouseTracking() {
        // Remove existing monitor if any
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Monitor global mouse movement for per-pill proximity fade
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self = self else { return }

            let mouseLocation = NSEvent.mouseLocation

            // Find the closest window to the mouse
            var closestWindow: NSWindow?
            var closestDistance: CGFloat = .greatestFiniteMagnitude

            for window in self.notchWindows.values {
                let windowFrame = window.frame
                let expandedFrame = windowFrame.insetBy(dx: -50, dy: -50)

                if expandedFrame.contains(mouseLocation) {
                    let centerX = windowFrame.midX
                    let centerY = windowFrame.midY
                    let distance = hypot(mouseLocation.x - centerX, mouseLocation.y - centerY)
                    if distance < closestDistance {
                        closestDistance = distance
                        closestWindow = window
                    }
                }
            }

            Task { @MainActor in
                let state = NotchState.shared

                if let window = closestWindow {
                    let windowFrame = window.frame
                    // Store global screen coordinates (NotchView uses .global coordinate space)
                    state.mousePosition = mouseLocation
                    state.isHovered = windowFrame.contains(mouseLocation)
                } else {
                    state.mousePosition = nil
                    state.isHovered = false
                }
            }
        }
    }

    private func setupObservers() {
        // Hide/show all windows when idle state changes
        NotchState.shared.$isIdle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isIdle in
                guard let self = self else { return }
                if isIdle {
                    self.notchWindows.values.forEach { $0.orderOut(nil) }
                } else {
                    self.notchWindows.values.forEach { $0.orderFrontRegardless() }
                }
            }
            .store(in: &cancellables)

        // Also hide when no sessions
        NotchState.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self = self else { return }
                if sessions.isEmpty {
                    self.notchWindows.values.forEach { $0.orderOut(nil) }
                }
            }
            .store(in: &cancellables)
    }

    private func startServer() {
        ClaudeCodeServer.shared.start()
    }

    // MARK: - Actions

    @objc func showNotch() {
        notchWindows.values.forEach { $0.orderFrontRegardless() }
    }

    @objc func hideNotch() {
        notchWindows.values.forEach { $0.orderOut(nil) }
    }

    @objc func focusActiveSession() {
        let state = NotchState.shared

        // Clear all pinned first
        state.pinnedProjectPaths.removeAll()

        // Pin the active session (or most recent)
        if let activeId = state.activeSessionId,
           let session = state.sessions[activeId] {
            state.pinProjectPath(session.projectPath)
        } else if let mostRecent = state.sessions.values.max(by: { $0.lastActivityTime < $1.lastActivityTime }) {
            state.pinProjectPath(mostRecent.projectPath)
        }

        // Show all notch windows
        notchWindows.values.forEach { $0.orderFrontRegardless() }
    }

    @objc func clearAllPinned() {
        NotchState.shared.pinnedProjectPaths.removeAll()
    }

    @objc func toggleAllMonitors() {
        let state = NotchState.shared
        state.showOnAllMonitors.toggle()

        // Update menu item checkmark
        if let menu = statusItem?.menu,
           let item = menu.item(withTag: 101) {
            item.state = state.showOnAllMonitors ? .on : .off
        }
    }

    @objc func showSetup() {
        showOnboardingWindow()
    }

    // MARK: - Onboarding

    private func checkAndShowOnboarding() async {
        guard !hasCheckedSetup else { return }
        hasCheckedSetup = true

        let status = await SetupManager.shared.checkSetup()

        if status == .notInstalled || status == .needsUpdate {
            // Auto-install hooks silently
            let success = await SetupManager.shared.installHooks()

            // Only show onboarding if installation failed
            if !success {
                showOnboardingWindow()
            }
        }
    }

    private func showOnboardingWindow() {
        // Don't show multiple
        if onboardingWindow != nil { return }

        let onboardingView = OnboardingView(
            setupManager: SetupManager.shared,
            isPresented: Binding(
                get: { self.onboardingWindow != nil },
                set: { if !$0 { self.hideOnboardingWindow() } }
            ),
            onComplete: { [weak self] in
                self?.hideOnboardingWindow()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "cookinn.notch Setup"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false

        // Handle window close button
        window.delegate = self

        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideOnboardingWindow() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window == onboardingWindow {
            onboardingWindow = nil
        }
    }
}
