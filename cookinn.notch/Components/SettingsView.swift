//
//  SettingsView.swift
//  cookinn.notch
//
//  Consolidated settings view replacing menu bar items
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var openAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var alertSounds: Bool = NotchState.shared.alertSoundsEnabled
    @State private var showRalphLoops: Bool = NotchState.shared.showRalphLoops
    @State private var selectedDisplayID: UInt32? = NotchState.shared.selectedDisplayID
    @State private var showOnAllMonitors: Bool = NotchState.shared.showOnAllMonitors

    var body: some View {
        Form {
            // General
            Section("General") {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        toggleOpenAtLogin(newValue)
                    }

                Toggle("Alert Sounds", isOn: $alertSounds)
                    .onChange(of: alertSounds) { _, newValue in
                        NotchState.shared.alertSoundsEnabled = newValue
                    }
            }

            // Display
            Section("Display") {
                Picker("Show on", selection: displayBinding) {
                    Text("All Monitors").tag("all" as String)
                    ForEach(NSScreen.screens.indices, id: \.self) { index in
                        let screen = NSScreen.screens[index]
                        Text(screen.localizedName).tag(getDisplayID(for: screen))
                    }
                }
                .pickerStyle(.menu)
            }

            // Visual
            Section("Visual") {
                Toggle("Show Ralph Loops", isOn: $showRalphLoops)
                    .onChange(of: showRalphLoops) { _, newValue in
                        NotchState.shared.showRalphLoops = newValue
                    }
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Updates")
                    Spacer()
                    Text(UpdateChecker.shared.status.menuTitle)
                        .foregroundStyle(.secondary)
                    if UpdateChecker.shared.status.hasUpdate {
                        Button("Update") {
                            UpdateChecker.shared.performBrewUpgrade()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }

    // MARK: - Display Picker Binding

    private var displayBinding: Binding<String> {
        Binding(
            get: {
                if showOnAllMonitors {
                    return "all"
                }
                if let id = selectedDisplayID {
                    return String(id)
                }
                // Default to main screen
                if let mainScreen = NSScreen.main {
                    return getDisplayID(for: mainScreen)
                }
                return "all"
            },
            set: { newValue in
                if newValue == "all" {
                    showOnAllMonitors = true
                    selectedDisplayID = nil
                    NotchState.shared.showOnAllMonitors = true
                    NotchState.shared.selectedDisplayID = nil
                } else if let id = UInt32(newValue) {
                    showOnAllMonitors = false
                    selectedDisplayID = id
                    NotchState.shared.showOnAllMonitors = false
                    NotchState.shared.selectedDisplayID = id
                }
            }
        )
    }

    private func getDisplayID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(number.uint32Value)
        }
        return "0"
    }

    // MARK: - Open at Login

    private func toggleOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert on failure
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Version

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
