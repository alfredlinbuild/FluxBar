import AppKit
import Foundation

enum MenuBarModePreference: String, CaseIterable, Identifiable, Codable {
    case automatic
    case standard
    case compact
    case icon
    case singleMetric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .standard: return "Standard"
        case .compact: return "Compact"
        case .icon: return "Icon"
        case .singleMetric: return "Single Metric"
        }
    }
}

enum ResolvedMenuBarMode: String, Codable {
    case standard
    case compact
    case icon
    case singleMetric
}

enum SingleMetricKind: String, CaseIterable, Identifiable, Codable {
    case temperature
    case network
    case memory
    case cpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: return "Temperature"
        case .network: return "Network"
        case .memory: return "Memory"
        case .cpu: return "CPU Usage"
        }
    }
}

enum MenuBarModule: String, CaseIterable, Identifiable, Codable {
    case temperature
    case network
    case memory
    case cpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: return "Temperature"
        case .network: return "Network"
        case .memory: return "Memory"
        case .cpu: return "CPU Usage"
        }
    }
}

enum TopProcessSortMode: String, CaseIterable, Identifiable, Codable {
    case heatingImpact
    case cpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heatingImpact: return "Heating Impact"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        }
    }
}

enum OverviewFlexibleSlotMode: String, CaseIterable, Identifiable, Codable {
    case thermal
    case weather
    case focus
    case oscarDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thermal: return "Thermal"
        case .weather: return "Weather"
        case .focus: return "Focus"
        case .oscarDay: return "Oscar's Day"
        }
    }
}

enum RiskLevel: String, Codable {
    case low
    case moderate
    case high
    case critical

    var title: String {
        rawValue.capitalized
    }

    var tint: ColorToken {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

enum ColorToken {
    case green
    case yellow
    case orange
    case red

    var color: NSColor {
        switch self {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .orange: return .systemOrange
        case .red: return .systemRed
        }
    }
}

enum MemoryPressureLevel: String, Codable {
    case normal
    case elevated
    case high
}

enum ThermalStateDescriptor: String, Codable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .fair
        }
    }

    var title: String {
        rawValue.capitalized
    }
}

struct TemperatureSnapshot: Sendable, Codable {
    var cpuCelsius: Double?
    var gpuCelsius: Double?
    var sourceDescription: String
    var isAvailable: Bool

    static func unavailable(reason: String) -> TemperatureSnapshot {
        TemperatureSnapshot(
            cpuCelsius: nil,
            gpuCelsius: nil,
            sourceDescription: reason,
            isAvailable: false
        )
    }
}

struct TopProcess: Identifiable, Hashable, Sendable, Codable {
    let id: Int32
    let pid: Int32
    let name: String
    let command: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let networkHint: String?
    let impactTags: [String]
    let heatingScore: Double
}

enum TrendWindow: String, CaseIterable, Identifiable, Codable {
    case oneMinute
    case fiveMinutes
    case thirtyMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .thirtyMinutes: return "30m"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 5 * 60
        case .thirtyMinutes: return 30 * 60
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable, Codable {
    case cpu
    case memory
    case network
    case temperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .temperature: return "Temperature"
        }
    }
}

struct SystemSnapshot: Sendable, Codable {
    let timestamp: Date
    let cpuUsagePercent: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let swapUsedBytes: UInt64
    let memoryPressure: MemoryPressureLevel
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let temperature: TemperatureSnapshot
    let thermalState: ThermalStateDescriptor
    let topProcesses: [TopProcess]

    func updating(topProcesses: [TopProcess]) -> SystemSnapshot {
        SystemSnapshot(
            timestamp: timestamp,
            cpuUsagePercent: cpuUsagePercent,
            memoryUsedBytes: memoryUsedBytes,
            memoryTotalBytes: memoryTotalBytes,
            swapUsedBytes: swapUsedBytes,
            memoryPressure: memoryPressure,
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond,
            temperature: temperature,
            thermalState: thermalState,
            topProcesses: topProcesses
        )
    }
}

struct HeatAssessment: Sendable, Codable {
    let riskLevel: RiskLevel
    let primaryFactors: [String]
    let secondaryFactors: [String]
    let confidence: Double
    let explanation: String
    let suggestions: [String]

    static let unavailable = HeatAssessment(
        riskLevel: .low,
        primaryFactors: ["Insufficient data"],
        secondaryFactors: [],
        confidence: 0.2,
        explanation: "FluxBar is still collecting enough runtime samples to assess heating factors.",
        suggestions: ["Keep FluxBar running for a few more refresh cycles."]
    )
}

struct FluxAlert: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let level: RiskLevel
    let title: String
    let message: String
    let symbolName: String
}
