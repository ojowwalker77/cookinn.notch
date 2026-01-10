//
//  AudioManager.swift
//  cookinn.notch
//
//  Manages audio playback for notifications (permission alerts)
//  Escalating reminders: 0s, 10s, 30s, 60s
//

import Foundation
import AVFoundation

final class AudioManager {
    static let shared = AudioManager()

    private var audioPlayer: AVAudioPlayer?
    private var reminderTimers: [Timer] = []
    private var isWaitingActive = false

    private init() {}

    /// Start escalating alert sequence when Claude needs user permission
    /// Plays at: 0s, 10s, 30s, 60s
    func startWaitingAlerts() {
        // Don't restart if already active
        guard !isWaitingActive else { return }
        isWaitingActive = true

        // Play immediately
        playAlertSoundIfEnabled()

        // Schedule escalating reminders
        let delays: [TimeInterval] = [10, 30, 60]  // seconds from now
        for delay in delays {
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] timer in
                defer { self?.reminderTimers.removeAll { $0 === timer } }
                guard self?.isWaitingActive == true else { return }
                self?.playAlertSoundIfEnabled()
            }
            reminderTimers.append(timer)
        }
    }

    /// Play alert sound only if enabled in settings
    private func playAlertSoundIfEnabled() {
        // Check setting on main thread
        Task { @MainActor in
            guard NotchState.shared.alertSoundsEnabled else { return }
            self.playAlertSound()
        }
    }

    /// Stop all alerts and cancel pending reminders
    func stopWaitingAlerts() {
        isWaitingActive = false
        // Cancel all pending timers
        for timer in reminderTimers {
            timer.invalidate()
        }
        reminderTimers.removeAll()
        stopSound()
    }

    /// Play the alert sound once
    private func playAlertSound() {
        // Stop any currently playing sound to avoid overlap
        audioPlayer?.stop()

        // Find the alert.mp3 in the bundle
        guard let soundURL = Bundle.main.url(forResource: "alert", withExtension: "mp3") else {
            print("[AudioManager] alert.mp3 not found in bundle")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.numberOfLoops = 0  // Play once
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("[AudioManager] Failed to play alert sound: \(error.localizedDescription)")
        }
    }

    /// Stop any currently playing sound
    func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
