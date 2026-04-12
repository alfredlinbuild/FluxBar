import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DiagnosticExporter {
    static func export(snapshot: SystemSnapshot?, assessment: HeatAssessment) -> String {
        guard let snapshot else {
            return "No snapshot available to export yet."
        }

        let panel = NSSavePanel()
        panel.title = "Export FluxBar Diagnostic Summary"
        panel.message = "Save a plain-text snapshot of the current FluxBar diagnosis."
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = defaultFilename(for: snapshot.timestamp)

        guard panel.runModal() == .OK, let url = panel.url else {
            return "Export cancelled."
        }

        do {
            try diagnosticText(snapshot: snapshot, assessment: assessment)
                .write(to: url, atomically: true, encoding: .utf8)
            return "Saved summary to \(url.path)."
        } catch {
            return "Failed to export summary: \(error.localizedDescription)"
        }
    }

    private static func defaultFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "FluxBar-Diagnostic-\(formatter.string(from: date)).txt"
    }

    private static func diagnosticText(snapshot: SystemSnapshot, assessment: HeatAssessment) -> String {
        let temperatureLine: String
        if snapshot.temperature.isAvailable {
            temperatureLine = "CPU \(MetricsFormatter.temperatureWithUnit(snapshot.temperature.cpuCelsius)), GPU \(MetricsFormatter.temperatureWithUnit(snapshot.temperature.gpuCelsius))"
        } else {
            temperatureLine = "Unavailable (\(snapshot.temperature.sourceDescription))"
        }

        let processes = snapshot.topProcesses.isEmpty
            ? "- None sampled yet"
            : snapshot.topProcesses.map {
                "- \($0.name): CPU \(MetricsFormatter.percent($0.cpuPercent)), MEM \(MetricsFormatter.bytes($0.memoryBytes)), Tags \($0.impactTags.joined(separator: ", "))"
            }.joined(separator: "\n")

        return """
        FluxBar Diagnostic Summary
        Generated: \(snapshot.timestamp.formatted(date: .abbreviated, time: .standard))

        Overview
        - CPU Usage: \(MetricsFormatter.percent(snapshot.cpuUsagePercent))
        - Memory: \(MetricsFormatter.bytes(snapshot.memoryUsedBytes)) / \(MetricsFormatter.bytes(snapshot.memoryTotalBytes))
        - Swap Used: \(MetricsFormatter.bytes(snapshot.swapUsedBytes))
        - Memory Pressure: \(snapshot.memoryPressure.rawValue.capitalized)
        - Download: \(MetricsFormatter.throughput(snapshot.downloadBytesPerSecond))
        - Upload: \(MetricsFormatter.throughput(snapshot.uploadBytesPerSecond))
        - Temperature: \(temperatureLine)
        - Thermal State: \(snapshot.thermalState.title)

        Heat Assessment
        - Risk Level: \(assessment.riskLevel.title)
        - Confidence: \(Int(assessment.confidence * 100))%
        - Explanation: \(assessment.explanation)
        - Primary Factors: \(assessment.primaryFactors.joined(separator: ", "))
        - Secondary Factors: \(assessment.secondaryFactors.joined(separator: ", "))
        - Suggestions: \(assessment.suggestions.joined(separator: " | "))

        Top Processes
        \(processes)
        """
    }
}
