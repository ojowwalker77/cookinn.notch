//
//  TTSManager.swift
//  cookinn.notch
//
//  Text-to-Speech manager using ElevenLabs Flash v2.5 API
//  Falls back to macOS `say` command if no API key configured
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TTSManager: ObservableObject {
    static let shared = TTSManager()

    // ElevenLabs config - Rachel (standard voice)
    private let voiceId = "21m00Tcm4TlvDq8ikWAM"
    private let modelId = "eleven_flash_v2_5"
    private let apiBaseURL = "https://api.elevenlabs.io/v1/text-to-speech"

    // Audio playback (for ElevenLabs)
    private var audioPlayer: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?

    // Fallback: macOS say process
    private var sayProcess: Process?
    private var isPaused = false

    // Progress tracking (ElevenLabs only)
    @Published var progress: Double = 0.0  // 0.0-1.0
    @Published var duration: TimeInterval = 0.0
    @Published var isLoading: Bool = false  // True while waiting for ElevenLabs response
    private var progressTimer: Timer?

    // Playback rate (ElevenLabs only)
    private(set) var playbackRate: Float = 1.0
    static let availableRates: [Float] = [1.0, 1.25, 1.5]

    private init() {}

    /// Speak text using ElevenLabs (or fallback to `say`)
    func speak(_ text: String) {
        stop()

        let cleaned = stripMarkdown(text)
        guard !cleaned.isEmpty else { return }

        // Try ElevenLabs if API key exists
        if let apiKey = KeychainManager.getAPIKey(), !apiKey.isEmpty {
            speakWithElevenLabs(cleaned, apiKey: apiKey)
        } else {
            speakWithSay(cleaned)
        }
    }

    // MARK: - ElevenLabs

    private func speakWithElevenLabs(_ text: String, apiKey: String) {
        isLoading = true
        currentTask = Task {
            do {
                let audioData = try await fetchElevenLabsAudio(text: text, apiKey: apiKey)
                await MainActor.run { isLoading = false }
                try await playAudioData(audioData)
            } catch {
                await MainActor.run { isLoading = false }
                print("[TTSManager] ElevenLabs failed: \(error), falling back to say")
                // Fallback to say on error
                speakWithSay(text)
            }
        }
    }

    private func fetchElevenLabsAudio(text: String, apiKey: String) async throws -> Data {
        guard let url = URL(string: "\(apiBaseURL)/\(voiceId)") else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return data
    }

    private func playAudioData(_ data: Data) async throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.enableRate = true
        audioPlayer?.rate = playbackRate
        audioPlayer?.prepareToPlay()
        duration = audioPlayer?.duration ?? 0
        audioPlayer?.play()
        startProgressTimer()
    }

    // MARK: - Fallback: macOS say

    private func speakWithSay(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "Karen", text]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            sayProcess = process
            isPaused = false
        } catch {
            print("[TTSManager] Failed to start say process: \(error)")
        }
    }

    // MARK: - Playback Control

    /// Pause the current speech
    func pause() {
        // ElevenLabs audio
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            stopProgressTimer()
            return
        }

        // Fallback say process
        guard let process = sayProcess, process.isRunning, !isPaused else { return }
        kill(process.processIdentifier, SIGSTOP)
        isPaused = true
    }

    /// Resume paused speech
    func resume() {
        // ElevenLabs audio
        if let player = audioPlayer, !player.isPlaying {
            player.play()
            startProgressTimer()
            return
        }

        // Fallback say process
        guard let process = sayProcess, isPaused else { return }
        kill(process.processIdentifier, SIGCONT)
        isPaused = false
    }

    /// Stop and terminate the current speech
    func stop() {
        // Cancel pending ElevenLabs request
        currentTask?.cancel()
        currentTask = nil

        // Stop progress tracking
        stopProgressTimer()
        progress = 0.0
        duration = 0.0
        isLoading = false

        // Stop ElevenLabs audio
        audioPlayer?.stop()
        audioPlayer = nil

        // Stop say process
        if let process = sayProcess {
            if isPaused {
                kill(process.processIdentifier, SIGCONT)
            }
            process.terminate()
            sayProcess = nil
        }
        isPaused = false
    }

    // MARK: - Rate & Seek (ElevenLabs only)

    /// Set playback rate (1.0, 1.25, 1.5)
    func setRate(_ rate: Float) {
        playbackRate = rate
        audioPlayer?.rate = rate
    }

    /// Cycle to next playback rate
    func cycleRate() {
        guard let currentIndex = Self.availableRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            audioPlayer?.rate = 1.0
            return
        }
        let nextIndex = (currentIndex + 1) % Self.availableRates.count
        setRate(Self.availableRates[nextIndex])
    }

    /// Seek to a position (0.0-1.0)
    func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let targetTime = player.duration * progress
        player.currentTime = targetTime
        self.progress = progress
    }

    /// Whether using ElevenLabs (supports speed/seek) vs say fallback
    var supportsAdvancedControls: Bool {
        audioPlayer != nil
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer else {
            progress = 0.0
            return
        }
        if player.duration > 0 {
            progress = player.currentTime / player.duration
        }
        // Auto-stop when finished
        if !player.isPlaying && progress > 0.99 {
            progress = 1.0
            stopProgressTimer()
        }
    }

    /// Whether speech is currently active (playing or paused)
    var isActive: Bool {
        if audioPlayer?.isPlaying == true { return true }
        if sayProcess?.isRunning == true { return true }
        return false
    }

    // MARK: - Markdown Stripping

    /// Remove markdown formatting to make text more natural for TTS
    private func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove code blocks (```...```)
        result = result.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove inline code (`...`)
        result = result.replacingOccurrences(
            of: "`[^`]+`",
            with: "",
            options: .regularExpression
        )

        // Remove headers (# Header)
        result = result.replacingOccurrences(
            of: "(?m)^#{1,6}\\s*",
            with: "",
            options: .regularExpression
        )

        // Remove bold (**text**)
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "$1",
            options: .regularExpression
        )

        // Remove italic (*text*)
        result = result.replacingOccurrences(
            of: "\\*([^*]+)\\*",
            with: "$1",
            options: .regularExpression
        )

        // Remove list markers (-, +, *)
        result = result.replacingOccurrences(
            of: "(?m)^[\\-\\+\\*]\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove numbered list markers (1., 2., etc.)
        result = result.replacingOccurrences(
            of: "(?m)^\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove links [text](url) -> text
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )

        // Collapse multiple newlines
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid ElevenLabs URL"
        case .invalidResponse:
            return "Invalid response from ElevenLabs"
        case .apiError(let code, let message):
            return "ElevenLabs API error (\(code)): \(message)"
        }
    }
}
