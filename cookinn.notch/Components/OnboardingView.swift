//
//  OnboardingView.swift
//  cookinn.notch
//
//  First-run setup - minimal and clean.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var setupManager: SetupManager
    @Binding var isPresented: Bool
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .cornerRadius(28)
                    .shadow(color: .white.opacity(0.1), radius: 20, y: 4)
            }

            // Title
            VStack(spacing: 8) {
                Text("cookinn.notch")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text("See Claude Code activity in your menu bar")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action area
            VStack(spacing: 12) {
                if setupManager.setupStatus == .installing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(height: 44)

                } else if setupManager.setupStatus == .installed {
                    Text("Ready")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                        .frame(height: 20)

                    Button("Done") {
                        onComplete()
                        isPresented = false
                    }
                    .buttonStyle(PrimaryButtonStyle())

                } else if let error = setupManager.installError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)

                    Button("Retry") {
                        Task { await setupManager.installHooks() }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                } else {
                    Button("Set Up") {
                        Task { await setupManager.installHooks() }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Text("Installs a small hook to ~/.config")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 80)

            Spacer()

            // Skip
            if setupManager.setupStatus != .installed {
                Button("Skip") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 40)
        .frame(width: 360, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: setupManager.setupStatus)
    }
}

// Clean button style
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 120, height: 36)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

#Preview {
    OnboardingView(
        setupManager: SetupManager.shared,
        isPresented: .constant(true),
        onComplete: {}
    )
}
