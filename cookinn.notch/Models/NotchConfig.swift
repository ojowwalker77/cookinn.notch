//
//  NotchConfig.swift
//  cookinn.notch
//
//  v2.0 Semantic Visual Language Configuration
//  Category-based design with thermal color spectrum
//

import Foundation
import SwiftUI

// MARK: - Config Root

struct NotchConfig: Codable {
    let version: String
    let designSystem: DesignSystem?
    let categories: [String: CategoryConfig]
    let tools: [String: ToolConfig]
    let states: [String: StateConfig]
    let patterns: [String: PatternConfig]
    let colors: [String: ColorConfig]
    let attentionLevels: [String: AttentionConfig]?
    let durationEvolution: [String: DurationConfig]?
    let defaults: DefaultsConfig

    enum CodingKeys: String, CodingKey {
        case version
        case designSystem = "design_system"
        case categories, tools, states, patterns, colors
        case attentionLevels = "attention_levels"
        case durationEvolution = "duration_evolution"
        case defaults
    }
}

struct DesignSystem: Codable {
    let philosophy: String?
    let principle: String?
}

// MARK: - Category (the core of v2.0)

struct CategoryConfig: Codable {
    let description: String?
    let color: String
    let pattern: String
    let intensity: Int?
    let attention: String?
}

// MARK: - Tool (now references category)

struct ToolConfig: Codable {
    let category: String?
    let displayName: String
    let color: String?      // Override
    let pattern: String?    // Override
}

// MARK: - State

struct StateConfig: Codable {
    let category: String?
    let displayName: String
    let color: String?
    let pattern: String?
    let noTimeout: Bool?
    let funVerbs: [String]?
}

// MARK: - Pattern (with sequence support)

struct PatternConfig: Codable {
    let description: String?
    let mode: String           // "sequence", "random", "breathe", "static"
    let sequence: [[Int]]?     // For sequence mode
    let litRange: [Int]?       // For random mode [min, max]
    let interval: Double
}

// MARK: - Color

struct ColorConfig: Codable {
    let hex: String
    let swiftUI: String
}

// MARK: - Attention Level

struct AttentionConfig: Codable {
    let opacity: [Double]
    let pulse: Bool?
}

// MARK: - Duration Evolution

struct DurationConfig: Codable {
    let until: Int?
    let speedMult: Double
}

// MARK: - Defaults

struct DefaultsConfig: Codable {
    let unknownTool: UnknownToolConfig
    let activityTimeout: Int
    let idleTimeout: Int
    let gracePeriod: Int?
}

struct UnknownToolConfig: Codable {
    let category: String?
    let displayName: String
}

// MARK: - Resolved Tool Info (computed from category + overrides)

struct ResolvedToolInfo {
    let displayName: String
    let color: String
    let pattern: String
    let intensity: Int
    let attention: String
}

// MARK: - Config Manager (Singleton)

final class ConfigManager: @unchecked Sendable {
    static let shared = ConfigManager()

    private(set) var config: NotchConfig?

    private init() {
        loadConfig()
    }

    func loadConfig() {
        guard let url = Bundle.main.url(forResource: "notch-config", withExtension: "json") else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            config = try JSONDecoder().decode(NotchConfig.self, from: data)
        } catch {
            // Config loading failed - will use defaults
        }
    }

    // MARK: - Tool Resolution (category-based)

    func resolveToolInfo(for name: String) -> ResolvedToolInfo {
        let toolKey = name.lowercased()

        // Handle MCP tools
        let lookupKey = toolKey.hasPrefix("mcp__") ? "mcp" : toolKey

        // Get tool config
        guard let toolConfig = config?.tools[lookupKey] else {
            return resolveUnknownTool()
        }

        // Get category config
        let categoryConfig = toolConfig.category.flatMap { config?.categories[$0] }

        // Resolve with category as base, tool as override
        return ResolvedToolInfo(
            displayName: toolConfig.displayName,
            color: toolConfig.color ?? categoryConfig?.color ?? "slate",
            pattern: toolConfig.pattern ?? categoryConfig?.pattern ?? "breathe",
            intensity: categoryConfig?.intensity ?? 2,
            attention: categoryConfig?.attention ?? "ambient"
        )
    }

    func resolveStateInfo(for name: String) -> ResolvedToolInfo {
        guard let stateConfig = config?.states[name.lowercased()] else {
            return ResolvedToolInfo(
                displayName: name.capitalized,
                color: "slate",
                pattern: "dormant",
                intensity: 1,
                attention: "peripheral"
            )
        }

        // Get category if specified
        let categoryConfig = stateConfig.category.flatMap { config?.categories[$0] }

        return ResolvedToolInfo(
            displayName: stateConfig.displayName,
            color: stateConfig.color ?? categoryConfig?.color ?? "slate",
            pattern: stateConfig.pattern ?? categoryConfig?.pattern ?? "dormant",
            intensity: categoryConfig?.intensity ?? 1,
            attention: categoryConfig?.attention ?? "peripheral"
        )
    }

    private func resolveUnknownTool() -> ResolvedToolInfo {
        let unknown = config?.defaults.unknownTool
        let categoryConfig = unknown?.category.flatMap { config?.categories[$0] }

        return ResolvedToolInfo(
            displayName: unknown?.displayName ?? "Working",
            color: categoryConfig?.color ?? "purple",
            pattern: categoryConfig?.pattern ?? "breathe",
            intensity: categoryConfig?.intensity ?? 2,
            attention: categoryConfig?.attention ?? "ambient"
        )
    }

    // MARK: - Pattern Access

    func patternConfig(for name: String) -> PatternConfig? {
        return config?.patterns[name]
    }

    // MARK: - Color Helpers

    func swiftUIColor(for name: String) -> Color {
        // First check config mapping
        if let colorConfig = config?.colors[name] {
            return colorFromSwiftUIName(colorConfig.swiftUI)
        }
        // Fallback to direct name
        return colorFromSwiftUIName(name)
    }

    private func colorFromSwiftUIName(_ name: String) -> Color {
        switch name.lowercased() {
        case "cyan": return .cyan
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "blue": return .blue
        case "indigo": return .indigo
        case "pink": return .pink
        case "teal": return .teal
        case "mint": return .mint
        case "gray", "slate": return .gray
        default: return .gray
        }
    }

    // MARK: - Attention Helpers

    func attentionOpacity(for level: String) -> (min: Double, max: Double) {
        guard let attention = config?.attentionLevels?[level],
              attention.opacity.count >= 2 else {
            return (0.6, 0.85)
        }
        return (attention.opacity[0], attention.opacity[1])
    }

    // MARK: - Timeouts

    var activityTimeout: TimeInterval {
        TimeInterval(config?.defaults.activityTimeout ?? 30)
    }

    var idleTimeout: TimeInterval {
        TimeInterval(config?.defaults.idleTimeout ?? 15)
    }

    var gracePeriod: TimeInterval {
        TimeInterval(config?.defaults.gracePeriod ?? 3)
    }

    // MARK: - State Helpers

    /// Check if a state should skip timeout (e.g., thinking can run indefinitely)
    func stateHasNoTimeout(_ stateName: String) -> Bool {
        return config?.states[stateName.lowercased()]?.noTimeout ?? false
    }

    /// Get fun verbs for a state (used for long operations)
    func funVerbs(for stateName: String) -> [String]? {
        return config?.states[stateName.lowercased()]?.funVerbs
    }

    /// Get a random fun verb for a state
    func randomFunVerb(for stateName: String) -> String? {
        return funVerbs(for: stateName)?.randomElement()
    }

    // MARK: - Duration Evolution

    /// Get speed multiplier based on how long an operation has been running
    /// Returns 1.0 for short operations, decreasing for longer ones (calming effect)
    func durationSpeedMultiplier(seconds: TimeInterval) -> Double {
        guard let evolution = config?.durationEvolution else { return 1.0 }

        // Sort by 'until' value to check thresholds in order
        let sorted = evolution.sorted { (a, b) in
            let aUntil = a.value.until ?? Int.max
            let bUntil = b.value.until ?? Int.max
            return aUntil < bUntil
        }

        for (_, config) in sorted {
            if let until = config.until {
                if seconds < Double(until) {
                    return config.speedMult
                }
            } else {
                // null until means "forever" - this is the stuck state
                return config.speedMult
            }
        }

        return 1.0
    }
}

// MARK: - ActiveTool Extensions

extension ActiveTool {
    var resolvedInfo: ResolvedToolInfo {
        ConfigManager.shared.resolveToolInfo(for: name)
    }

    var configuredDisplayName: String {
        resolvedInfo.displayName
    }

    var configuredColor: Color {
        ConfigManager.shared.swiftUIColor(for: resolvedInfo.color)
    }

    var configuredPattern: String {
        resolvedInfo.pattern
    }

    var configuredIntensity: Int {
        resolvedInfo.intensity
    }

    var configuredAttention: String {
        resolvedInfo.attention
    }
}
