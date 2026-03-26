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
import ServiceManagement

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
    var settingsWindow: NSWindow?
    private var hasCheckedSetup = false
    private let openAtLoginPromptedKey = "NotchHasPromptedOpenAtLogin"
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitor: Any?
    private var screenObserver: Any?
    private var lastMouseUpdate: Date = .distantPast
    private var lastMouseLocation: NSPoint = .zero
    private let mouseUpdateInterval: TimeInterval = 0.2  // 5fps throttle (was 10fps)
    private let mouseMovementThreshold: CGFloat = 5.0    // Skip updates for tiny movements

    // Notch dimensions (measured from screen)
    private var notchWidth: CGFloat = 180
    private var notchHeight: CGFloat = 32

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load config first
        _ = ConfigManager.shared

        // Check setup status and show onboarding if needed
        Task { @MainActor in
            await checkAndShowOnboarding()
            promptOpenAtLoginIfNeeded()
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
            mouseMonitor = nil
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
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
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        self.statusItem?.menu = menu

        setupUpdateChecker()
    }

    private func setupUpdateChecker() {
        // Subscribe to update status changes
        UpdateChecker.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateVersionMenuItem(status)
            }
            .store(in: &cancellables)
    }

    private func updateVersionMenuItem(_ status: UpdateStatus) {
        // Version info now shown in Settings view only
        // This method kept for UpdateChecker subscription but no menu update needed
    }

    // Note: startStatusUpdates and updateStatusIcon removed - they were no-op placeholders.
    // If future icon updates are needed, implement here with proper state-based logic.

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

        let state = NotchState.shared

        // Determine which screens to use
        let screens: [NSScreen]
        if state.showOnAllMonitors {
            screens = NSScreen.screens
        } else if let selected = state.selectedScreen {
            // User selected a specific monitor
            screens = [selected]
        } else {
            // Fallback: selected monitor disconnected, or nil (use main)
            // Only reset if the selected display is actually disconnected (avoids recursive trigger)
            if let currentID = state.selectedDisplayID,
               !NSScreen.screens.contains(where: { getDisplayID(for: $0) == currentID }) {
                state.selectedDisplayID = nil
            }
            screens = NSScreen.main.map { [$0] } ?? []
        }

        for screen in screens {
            createWindowForScreen(screen)
        }

        // Set up mouse tracking for all windows
        setupMouseTracking()

        // Show windows immediately if there's active content
        if !state.isIdle && !state.sessions.isEmpty {
            notchWindows.values.forEach { $0.orderFrontRegardless() }
        }
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
        window.ignoresMouseEvents = true  // Click-through - hover detection via global mouse monitor

        // Position at TOP-RIGHT of this screen, below menu bar
        let menuBarHeight = screenFrame.maxY - screen.visibleFrame.maxY
        let paddingX: CGFloat = 0
        let paddingY: CGFloat = 0
        window.setFrameOrigin(NSPoint(
            x: screenFrame.maxX - window.frame.width - paddingX,
            y: screenFrame.maxY - menuBarHeight - window.frame.height - paddingY
        ))

        let contentView = NotchView(displayID: displayID)
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

        // Watch showOnAllMonitors changes
        NotchState.shared.showOnAllMonitorsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupNotchWindows()
            }
            .store(in: &cancellables)

        // Watch selectedDisplayID changes
        NotchState.shared.selectedDisplayIDPublisher
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

        // Monitor global mouse movement for per-screen hover detection
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self = self else { return }

            // OPTIMIZATION: Skip if windows are not visible
            let hasVisibleWindows = self.notchWindows.values.contains { $0.isVisible }
            guard hasVisibleWindows else { return }

            // Throttle: skip if too soon since last update (5fps)
            let now = Date()
            guard now.timeIntervalSince(self.lastMouseUpdate) >= self.mouseUpdateInterval else { return }

            let mouseLocation = NSEvent.mouseLocation

            // Skip if mouse hasn't moved significantly (5px threshold)
            let dx = mouseLocation.x - self.lastMouseLocation.x
            let dy = mouseLocation.y - self.lastMouseLocation.y
            let movement = sqrt(dx * dx + dy * dy)
            guard movement >= self.mouseMovementThreshold else { return }

            self.lastMouseUpdate = now
            self.lastMouseLocation = mouseLocation
            let windows = self.notchWindows  // Capture for async

            // Check each display independently
            Task { @MainActor in
                let state = NotchState.shared
                var newHoveredIDs: Set<String> = []

                // Snapshot sessions to avoid race conditions during calculation
                let sessionsSnapshot = state.sessions.values
                let pinnedPathsSnapshot = state.pinnedProjectPaths

                // Calculate dynamic pill height based on pinned session count
                let pinnedCount = sessionsSnapshot.filter { pinnedPathsSnapshot.contains($0.normalizedPath) }.count
                let sessionCount = max(1, pinnedCount)  // At least 1 for idle pill
                let sessionHeight: CGFloat = 42
                let spacing: CGFloat = 4
                let padding: CGFloat = 20
                let pillHeight = CGFloat(sessionCount) * sessionHeight + CGFloat(sessionCount - 1) * spacing + padding

                for (displayID, window) in windows {
                    let windowFrame = window.frame
                    let pillFrame = CGRect(
                        x: windowFrame.minX,
                        y: windowFrame.maxY - pillHeight,
                        width: windowFrame.width,
                        height: pillHeight
                    )
                    if pillFrame.contains(mouseLocation) {
                        newHoveredIDs.insert(displayID)
                    }
                }

                // Only update if changed
                if state.hoveredDisplayIDs != newHoveredIDs {
                    state.hoveredDisplayIDs = newHoveredIDs
                }
            }
        }
    }

    private func setupObservers() {
        // Hide/show all windows when idle state changes
        NotchState.shared.isIdlePublisher
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
        NotchState.shared.sessionsPublisher
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

    @objc func openReleasesPage() {
        if let url = UpdateChecker.shared.releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func performUpdate() {
        UpdateChecker.shared.performBrewUpgrade()
    }

    @objc func restartAfterUpdate() {
        UpdateChecker.shared.restartApp()
    }

    // MARK: - Display Selection

    private func getDisplayID(for screen: NSScreen) -> UInt32 {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return 0
    }

    @objc func showSettings() {
        // If window exists and is visible, just bring to front
        if let existing = settingsWindow {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            settingsWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "cookinn.notch Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func promptOpenAtLoginIfNeeded() {
        // Only prompt once ever
        guard !UserDefaults.standard.bool(forKey: openAtLoginPromptedKey) else { return }

        // Mark as prompted before showing (so we never ask again even if dismissed)
        UserDefaults.standard.set(true, forKey: openAtLoginPromptedKey)

        let alert = NSAlert()
        alert.messageText = "Open at Login?"
        alert.informativeText = "Would you like cookinn.notch to start automatically when you log in?"
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            try? SMAppService.mainApp.register()
        }
    }

    private func showOnboardingWindow() {
        // If window exists and is visible, just bring to front
        if let existing = onboardingWindow {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            // Window exists but not visible - clean up stale reference
            onboardingWindow = nil
        }

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
        guard let window = notification.object as? NSWindow else { return }

        if window == onboardingWindow {
            onboardingWindow = nil
        } else if window == settingsWindow {
            settingsWindow = nil
        }
    }
}
