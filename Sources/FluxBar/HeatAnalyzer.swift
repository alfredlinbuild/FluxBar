import Foundation

struct HeatAnalyzer {
    func analyze(
        snapshot: SystemSnapshot,
        history: [SystemSnapshot],
        configuration: MonitoringConfiguration
    ) -> HeatAssessment {
        let recentWindow = history.filter { snapshot.timestamp.timeIntervalSince($0.timestamp) <= 45 }
        let averageCPU = average(of: recentWindow.map(\.cpuUsagePercent))
        let averageMemoryRatio = average(of: recentWindow.map { memoryRatio(for: $0) })
        let averageNetwork = average(of: recentWindow.map { $0.downloadBytesPerSecond + $0.uploadBytesPerSecond })
        let hotProcesses = snapshot.topProcesses.filter { $0.heatingScore >= 35 || $0.cpuPercent >= 30 }
        let memoryRatioNow = memoryRatio(for: snapshot)
        let temperatureSignal = max(snapshot.temperature.cpuCelsius ?? 0, snapshot.temperature.gpuCelsius ?? 0)

        var score = 0.0
        var primary: [String] = []
        var secondary: [String] = []
        var explanationBits: [String] = []
        var suggestions: [String] = []
        var signalCount = 0.0

        if averageCPU >= configuration.cpuHighUsageThreshold || !hotProcesses.isEmpty {
            score += min(averageCPU / 1.8, 40)
            primary.append("Sustained CPU activity")
            explanationBits.append("CPU load has stayed elevated across recent samples.")
            suggestions.append("Pause or close the top CPU-heavy process first.")
            signalCount += 1
        } else if snapshot.cpuUsagePercent >= configuration.cpuHighUsageThreshold * 0.8 {
            score += 12
            secondary.append("Short CPU burst")
            signalCount += 1
        }

        if memoryRatioNow >= configuration.memoryHighWatermark || snapshot.memoryPressure == .high {
            score += 24
            primary.append("Memory pressure")
            explanationBits.append("High memory occupancy can trigger compression or swap work that adds heat.")
            suggestions.append("Close high-memory apps or large browser/tab groups.")
            signalCount += 1
        } else if averageMemoryRatio >= configuration.memoryHighWatermark * 0.9 || snapshot.memoryPressure == .elevated {
            score += 12
            secondary.append("Rising memory usage")
            signalCount += 1
        }

        if averageNetwork >= configuration.networkHighWatermarkBytesPerSecond {
            score += 18
            primary.append("Sustained network throughput")
            explanationBits.append("Large upload or download traffic is keeping radios and data handling active.")
            suggestions.append("Pause sync, download, or cloud backup activity if cooling down matters.")
            signalCount += 1
        } else if snapshot.downloadBytesPerSecond + snapshot.uploadBytesPerSecond >= configuration.networkHighWatermarkBytesPerSecond * 0.7 {
            score += 8
            secondary.append("Short network burst")
            signalCount += 1
        }

        if hotProcesses.count >= 2 {
            score += 14
            primary.append("Multiple active processes")
            explanationBits.append("Several busy processes are stacking load at the same time.")
            suggestions.append("Sort the process list by CPU and stop the top one or two offenders.")
            signalCount += 1
        }

        switch snapshot.thermalState {
        case .serious:
            score += 22
            primary.append("macOS thermal pressure is elevated")
            explanationBits.append("The system thermal state has already moved beyond nominal.")
            signalCount += 1
        case .critical:
            score += 32
            primary.append("macOS thermal pressure is critical")
            explanationBits.append("The system reports critical thermal pressure, so immediate load reduction is recommended.")
            signalCount += 1
        case .fair:
            score += 10
            secondary.append("macOS thermal state is fair")
            signalCount += 1
        case .nominal:
            break
        }

        if temperatureSignal >= 85 {
            score += 25
            primary.append("Temperature already elevated")
            explanationBits.append("Sensor-reported die temperature is already high.")
            signalCount += 1
        } else if temperatureSignal >= 72 {
            score += 12
            secondary.append("Temperature trending warm")
            signalCount += 1
        }

        let risk: RiskLevel
        switch score {
        case ..<18: risk = .low
        case ..<40: risk = .moderate
        case ..<65: risk = .high
        default: risk = .critical
        }

        let confidence = max(0.25, min(0.95, signalCount / 5 + (snapshot.temperature.isAvailable ? 0.1 : 0)))
        let explanation = explanationText(
            risk: risk,
            primary: primary,
            secondary: secondary,
            explanationBits: explanationBits,
            snapshot: snapshot
        )

        if suggestions.isEmpty {
            suggestions = defaultSuggestions(for: risk)
        }

        if !snapshot.temperature.isAvailable {
            secondary.append("Direct CPU/GPU temperature unavailable")
        }

        return HeatAssessment(
            riskLevel: risk,
            primaryFactors: primary.isEmpty ? ["No dominant heat driver detected"] : primary,
            secondaryFactors: secondary,
            confidence: confidence,
            explanation: explanation,
            suggestions: Array(NSOrderedSet(array: suggestions)) as? [String] ?? suggestions
        )
    }

    private func average(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func memoryRatio(for snapshot: SystemSnapshot) -> Double {
        guard snapshot.memoryTotalBytes > 0 else { return 0 }
        return Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes)
    }

    private func explanationText(
        risk: RiskLevel,
        primary: [String],
        secondary: [String],
        explanationBits: [String],
        snapshot: SystemSnapshot
    ) -> String {
        if risk == .low {
            return "No single factor currently stands out as a strong heating source. The system looks stable, though brief bursts may still occur."
        }

        var headline = "FluxBar estimates that "
        if let first = primary.first?.lowercased() {
            headline += "\(first) is the main reason your Mac feels warmer right now."
        } else {
            headline += "a combination of workload factors is raising system heat."
        }

        let detail = explanationBits.prefix(2).joined(separator: " ")
        let thermalSuffix: String
        if snapshot.temperature.isAvailable {
            thermalSuffix = " Current thermal state: \(snapshot.thermalState.title)."
        } else {
            thermalSuffix = " Direct temperature sensors are unavailable, so this remains a workload-based estimate."
        }

        if detail.isEmpty {
            let secondaryText = secondary.isEmpty ? "" : " Secondary contributors: \(secondary.joined(separator: ", "))."
            return headline + thermalSuffix + secondaryText
        }

        return headline + " " + detail + thermalSuffix
    }

    private func defaultSuggestions(for risk: RiskLevel) -> [String] {
        switch risk {
        case .low:
            return ["No immediate action needed."]
        case .moderate:
            return ["Reduce one active workload if you want cooler sustained operation."]
        case .high:
            return [
                "Close the busiest app or browser window first.",
                "Let large sync or download tasks finish later if they are not urgent.",
            ]
        case .critical:
            return [
                "Stop the top heavy process immediately.",
                "Reduce concurrent downloads, sync, or video work until thermal pressure drops.",
            ]
        }
    }
}
