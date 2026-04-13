import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    let snapshot: SystemSnapshot?
    let assessment: HeatAssessment
    let settings: FluxBarSettings

    var body: some View {
        let content = MenuBarPresentationEngine.makePresentation(
            snapshot: snapshot,
            assessment: assessment,
            settings: settings
        )

        Group {
            switch content.mode {
            case .standard, .compact:
                HStack(spacing: 6) {
                    Image(systemName: content.symbolName)
                        .font(.system(size: 15, weight: .semibold))

                    if let snapshot {
                        MenuBarDashboardCluster(
                            snapshot: snapshot,
                            settings: settings,
                            mode: content.mode
                        )
                    }
                }
            case .icon, .singleMetric:
                HStack(spacing: 6) {
                    Image(systemName: content.symbolName)
                        .font(.system(size: 12, weight: .semibold))

                    if let label = content.label {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: content.fixedWidth, alignment: .leading)
        .help(content.helpText)
    }
}

struct MenuBarPanelView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var settings: FluxBarSettings
    @Environment(\.openSettings) private var openSettings
    @State private var selectedTrendWindow: TrendWindow = .fiveMinutes
    @State private var overviewPrimaryRowHeight: CGFloat?
    @State private var oscarManualStatus: OscarDayStatus?
    @State private var oscarManualExpiresAt: Date?

    private let oscarManualOverrideDuration: TimeInterval = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                overviewSection
                trendsSection
                alertsSection
                if settings.showStatusSection {
                    statusSection
                }
                if settings.showTopProcessesSection {
                    processSection
                }
            }
            .padding(18)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.visible)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Flux")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("Bar")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .foregroundStyle(headerWordmarkColor)
    }

    private var headerWordmarkColor: Color {
        Color.primary
    }
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                StatusLine(title: "Run Mode", value: NotificationSupport.isAvailableInCurrentRunMode ? "Bundled .app" : "Development run")
                StatusLine(title: "Sampling", value: samplingStatusText)
                StatusLine(title: "History", value: historyStatusText)
                StatusLine(title: "Temperature", value: temperatureStatusText)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Overview")
                .font(.headline)

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    NetworkOverviewMetricCard(
                        title: "Network",
                        upload: snapshotValue { MetricsFormatter.throughput($0.uploadBytesPerSecond) },
                        download: snapshotValue { MetricsFormatter.throughput($0.downloadBytesPerSecond) },
                        footnote: networkFootnote
                    )
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(key: OverviewPrimaryRowHeightKey.self, value: geometry.size.height)
                        }
                    )

                    flexibleOverviewSlotCard
                    .frame(height: overviewPrimaryRowHeight, alignment: .topLeading)
                }
                .onPreferenceChange(OverviewPrimaryRowHeightKey.self) { height in
                    if height > 0 {
                        overviewPrimaryRowHeight = height
                    }
                }

                HStack(spacing: 10) {
                    OverviewMetricCard(
                        title: "CPU Usage",
                        value: snapshotValue { MetricsFormatter.percent($0.cpuUsagePercent) },
                        footnote: snapshotValue { cpuUsageFootnote(for: $0) }
                    )
                    OverviewMetricCard(
                        title: "Memory",
                        value: snapshotValue { memoryUsagePercent(for: $0) },
                        footnote: snapshotValue { memoryUsageFootnote(for: $0) }
                    )
                }

                HStack(spacing: 10) {
                    OverviewMetricCard(
                        title: "CPU Temp",
                        value: snapshotValue { MetricsFormatter.temperatureWithUnit($0.temperature.cpuCelsius) },
                        footnote: temperatureFootnote(source: \.temperature.sourceDescription)
                    )
                    OverviewMetricCard(
                        title: "GPU Temp",
                        value: snapshotValue { MetricsFormatter.temperatureWithUnit($0.temperature.gpuCelsius) },
                        footnote: snapshotValue { "Thermal \( $0.thermalState.title)" }
                    )
                }
            }
        }
    }

    private var alertsSection: some View {
        Group {
            if !monitor.activeAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alerts")
                        .font(.headline)

                    ForEach(monitor.activeAlerts) { alert in
                        AlertBanner(alert: alert)
                    }
                }
            }
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trends")
                    .font(.headline)

                Spacer()

                Picker("Range", selection: $selectedTrendWindow) {
                    ForEach(TrendWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                TrendMetricCard(
                    title: "CPU Usage",
                    value: snapshotValue { MetricsFormatter.percent($0.cpuUsagePercent) },
                    points: numericTrendValues(for: selectedTrendWindow, metric: .cpu),
                    tint: .orange,
                    valueFormatter: MetricsFormatter.percent
                )

                TrendMetricCard(
                    title: "Memory",
                    value: snapshotValue { MetricsFormatter.bytes($0.memoryUsedBytes) },
                    points: numericTrendValues(for: selectedTrendWindow, metric: .memory),
                    tint: .blue,
                    valueFormatter: { MetricsFormatter.bytes(UInt64($0)) }
                )

                TrendMetricCard(
                    title: "Network",
                    value: snapshotValue { MetricsFormatter.throughput($0.downloadBytesPerSecond + $0.uploadBytesPerSecond) },
                    points: numericTrendValues(for: selectedTrendWindow, metric: .network),
                    tint: .green,
                    valueFormatter: MetricsFormatter.throughput
                )

                TrendMetricCard(
                    title: "Temperature",
                    value: snapshotValue { primaryTemperatureValue(for: $0) },
                    points: temperatureTrendValues(for: selectedTrendWindow),
                    tint: .red,
                    valueFormatter: { MetricsFormatter.temperatureWithUnit($0) },
                    emptyMessage: "Direct sensor data unavailable"
                )
            }
        }
    }

    private var heatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heat Factors")
                .font(.headline)

            let assessment = monitor.latestAssessment

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RiskBadge(level: assessment.riskLevel)
                    Spacer()
                    Text("Confidence \(Int(assessment.confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(assessment.explanation)
                    .font(.callout)

                if !assessment.primaryFactors.isEmpty {
                    InsightList(title: "Primary", items: assessment.primaryFactors)
                }

                if !assessment.secondaryFactors.isEmpty {
                    InsightList(title: "Secondary", items: assessment.secondaryFactors)
                }

                InsightList(title: "Suggested Actions", items: assessment.suggestions)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top Processes")
                    .font(.headline)
                Spacer()
                Text("Sorted by \(settings.topProcessSortMode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let snapshot = monitor.latestSnapshot, !snapshot.topProcesses.isEmpty {
                VStack(spacing: 8) {
                    ForEach(snapshot.topProcesses) { process in
                        ProcessRow(process: process)
                    }
                }
            } else {
                EmptyStateCard(
                    title: "Waiting for process sample",
                    message: "FluxBar refreshes the top-process snapshot on a slower cadence to stay lightweight."
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                resetPanelViewState()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .fixedSize()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q")
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(footerBackground)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var footerBackground: some View {
        Rectangle()
            .fill(
                Color(nsColor: NSColor(name: nil) { appearance in
                    switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
                    case .darkAqua:
                        return NSColor(calibratedWhite: 0.15, alpha: 0.98)
                    default:
                        return NSColor(calibratedWhite: 0.96, alpha: 0.98)
                    }
                })
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: -2)
    }

    private func resetPanelViewState() {
        selectedTrendWindow = .fiveMinutes
        monitor.clearHistory()
    }

    private var samplingStatusText: String {
        guard let snapshot = monitor.latestSnapshot else {
            return "Collecting first sample"
        }

        let age = max(Int(Date().timeIntervalSince(snapshot.timestamp)), 0)
        return "Every \(String(format: "%.1f", settings.refreshInterval))s • last sample \(age)s ago"
    }

    private var historyStatusText: String {
        guard let first = monitor.history.first,
              let last = monitor.history.last else {
            return "No retained history yet"
        }

        let coverage = max(Int(last.timestamp.timeIntervalSince(first.timestamp)), 0)
        return "\(monitor.history.count) samples • \(coverage)s retained"
    }

    private var networkFootnote: String {
        guard let snapshot = monitor.latestSnapshot else {
            return "Last 1m ↓ —"
        }

        let downloadedBytes = recentDownloadedBytesLastMinute(fallbackRate: snapshot.downloadBytesPerSecond)
        return "Last 1m ↓ \(MetricsFormatter.bytes(downloadedBytes))"
    }

    private var temperatureStatusText: String {
        guard let snapshot = monitor.latestSnapshot else {
            return "Waiting for sensor probe"
        }

        if snapshot.temperature.isAvailable {
            return snapshot.temperature.sourceDescription
        }

        return "Thermal state only • \(snapshot.temperature.sourceDescription)"
    }

    private func snapshotValue(_ builder: (SystemSnapshot) -> String) -> String {
        guard let snapshot = monitor.latestSnapshot else { return "—" }
        return builder(snapshot)
    }

    private func thermalStateDisplay(for state: ThermalStateDescriptor) -> ThermalStateDisplay {
        switch state {
        case .nominal:
            return ThermalStateDisplay(title: "Chill", subtitle: "All good and easy", color: "cool")
        case .fair:
            return ThermalStateDisplay(title: "Warming up", subtitle: "Starting to feel warm", color: "warm")
        case .serious:
            return ThermalStateDisplay(title: "Hot and busy", subtitle: "Heat is building up", color: "hot")
        case .critical:
            return ThermalStateDisplay(title: "Overheating vibes", subtitle: "Needs a cooldown", color: "critical")
        @unknown default:
            return ThermalStateDisplay(title: "Chill", subtitle: "All good and easy", color: "cool")
        }
    }

    private func recentTrendText(_ keyPath: KeyPath<SystemSnapshot, Double>, formatter: (Double) -> String) -> String {
        let samples = monitor.history.suffix(8).map { $0[keyPath: keyPath] }
        guard samples.count >= 2 else { return "Recent trend pending" }
        let delta = samples.last! - samples.first!
        if abs(delta) < 0.1 {
            return "Stable"
        }
        return delta > 0 ? "Rising to \(formatter(samples.last!))" : "Falling to \(formatter(samples.last!))"
    }

    private func temperatureFootnote(source: KeyPath<SystemSnapshot, String>) -> String {
        guard let snapshot = monitor.latestSnapshot else { return "—" }
        return snapshot.temperature.isAvailable ? snapshot[keyPath: source] : "Unavailable: \(snapshot[keyPath: source])"
    }

    private func autoOscarDayStatus(at now: Date) -> OscarDayStatus {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 {
            return .outdoor
        }

        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        switch minutes {
        case ..<(8 * 60):
            return .breakfast
        case 8 * 60..<(11 * 60 + 30):
            return .outdoor
        case (11 * 60 + 30)..<(13 * 60 + 30):
            return .nap
        case (13 * 60 + 30)..<15 * 60:
            return .fruit
        case 15 * 60..<(16 * 60 + 30):
            return .outdoor
        default:
            return .fruit
        }
    }

    private func resolvedOscarDayStatus(at now: Date) -> OscarDayStatus {
        if let manual = oscarManualStatus,
           let expiresAt = oscarManualExpiresAt,
           now < expiresAt {
            return manual
        }
        return autoOscarDayStatus(at: now)
    }

    private func oscarDayState(for status: OscarDayStatus) -> OscarDayState {
        switch status {
        case .breakfast:
            return OscarDayState(
                emoji: "🥣",
                title: "Breakfast Time",
                tint: Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255)
            )
        case .nap:
            return OscarDayState(
                emoji: "🛏️",
                title: "Nap Time",
                tint: Color(red: 0xA8 / 255, green: 0x9A / 255, blue: 0xFF / 255)
            )
        case .outdoor:
            return OscarDayState(
                emoji: "🛝",
                title: "Outdoor Play",
                tint: Color(red: 0x7E / 255, green: 0xD3 / 255, blue: 0x92 / 255)
            )
        case .fruit:
            return OscarDayState(
                emoji: "🍓",
                title: "Fruit Snack",
                tint: Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0xB0 / 255)
            )
        }
    }

    private func cycleOscarDayStatus(at now: Date) {
        let current = resolvedOscarDayStatus(at: now)
        oscarManualStatus = current.next
        oscarManualExpiresAt = now.addingTimeInterval(oscarManualOverrideDuration)
    }

    private func oscarDayCountdownText(at now: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 {
            return "Weekend break"
        }

        let schoolStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let schoolEnd = calendar.date(bySettingHour: 16, minute: 30, second: 0, of: now) ?? now

        if now < schoolStart {
            return "School in \(formattedHourMinuteCountdown(from: now, to: schoolStart))"
        }
        if now < schoolEnd {
            return "Pickup in \(formattedHourMinuteCountdown(from: now, to: schoolEnd))"
        }

        var nextSchoolStart = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        nextSchoolStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: nextSchoolStart) ?? nextSchoolStart
        while true {
            let nextWeekday = calendar.component(.weekday, from: nextSchoolStart)
            if (2...6).contains(nextWeekday) {
                break
            }
            nextSchoolStart = calendar.date(byAdding: .day, value: 1, to: nextSchoolStart) ?? nextSchoolStart
            nextSchoolStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: nextSchoolStart) ?? nextSchoolStart
        }
        return "School in \(formattedHourMinuteCountdown(from: now, to: nextSchoolStart))"
    }

    private func formattedHourMinuteCountdown(from start: Date, to end: Date) -> String {
        let totalMinutes = max(Int(end.timeIntervalSince(start) / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    @ViewBuilder
    private var flexibleOverviewSlotCard: some View {
        FlexibleOverviewSlotCard(mode: $settings.overviewFlexibleSlotMode) {
            switch settings.overviewFlexibleSlotMode {
            case .thermal:
                ThermalStateOverviewCard(
                    value: snapshotValue { thermalStateDisplay(for: $0.thermalState).title },
                    statusLine: snapshotValue { thermalStateDisplay(for: $0.thermalState).subtitle },
                    tint: snapshotValue { thermalStateDisplay(for: $0.thermalState).color },
                    sourceLine: nil
                )
            case .focus:
                FocusOverviewCard(
                    value: "Deep Work",
                    footnote: "Protected time for building",
                    tint: Color(red: 0x8B / 255, green: 0x7C / 255, blue: 0xFF / 255)
                )
            case .oscarDay:
                let now = Date()
                let dayStatus = resolvedOscarDayStatus(at: now)
                let dayState = oscarDayState(for: dayStatus)
                OscarDayOverviewCard(
                    emoji: dayState.emoji,
                    title: dayState.title,
                    footnote: oscarDayCountdownText(at: now),
                    tint: dayState.tint,
                    onCycle: {
                        cycleOscarDayStatus(at: Date())
                    }
                )
            case .weather:
                WeatherOverviewCard(
                    temperature: "23°",
                    footnote: "Clear and bright outside",
                    symbolName: "sun.max.fill",
                    tint: Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255)
                )
            }
        }
    }

    private func numericTrendValues(for window: TrendWindow, metric: TrendMetric) -> [Double] {
        let cutoff = Date().addingTimeInterval(-window.duration)
        let samples = monitor.history.filter { $0.timestamp >= cutoff }

        return samples.map { snapshot in
            switch metric {
            case .cpu:
                return snapshot.cpuUsagePercent
            case .memory:
                return Double(snapshot.memoryUsedBytes)
            case .network:
                return snapshot.downloadBytesPerSecond + snapshot.uploadBytesPerSecond
            case .temperature:
                return 0
            }
        }
    }

    private func temperatureTrendValues(for window: TrendWindow) -> [Double] {
        let cutoff = Date().addingTimeInterval(-window.duration)
        return monitor.history
            .filter { $0.timestamp >= cutoff }
            .compactMap { $0.temperature.cpuCelsius ?? $0.temperature.gpuCelsius }
    }

    private func primaryTemperatureValue(for snapshot: SystemSnapshot) -> String {
        if let temperature = snapshot.temperature.cpuCelsius ?? snapshot.temperature.gpuCelsius {
            return MetricsFormatter.temperatureWithUnit(temperature)
        }
        return snapshot.thermalState.title
    }

    private func recentDownloadedBytesLastMinute(fallbackRate: Double) -> UInt64 {
        let window: TimeInterval = 60
        let now = Date()
        let cutoff = now.addingTimeInterval(-window)
        let samples = monitor.history
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        guard !samples.isEmpty else {
            return UInt64(max(fallbackRate, 0) * window)
        }

        if samples.count == 1 {
            let approxDuration = min(window, max(settings.refreshInterval, 1))
            return UInt64(max(samples[0].downloadBytesPerSecond, 0) * approxDuration)
        }

        var integrated: Double = 0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let dt = max(current.timestamp.timeIntervalSince(previous.timestamp), 0)
            let avgRate = max((previous.downloadBytesPerSecond + current.downloadBytesPerSecond) / 2, 0)
            integrated += avgRate * dt
        }

        if let last = samples.last {
            let tail = min(max(now.timeIntervalSince(last.timestamp), 0), max(settings.refreshInterval * 2, 1))
            integrated += max(last.downloadBytesPerSecond, 0) * tail
        }

        return UInt64(max(integrated, 0))
    }

    private func cpuUsageFootnote(for snapshot: SystemSnapshot) -> String {
        let totalCores = max(ProcessInfo.processInfo.processorCount, 1)
        let usagePercent = min(max(snapshot.cpuUsagePercent, 0), 100)
        let usedCores = (usagePercent / 100) * Double(totalCores)
        return String(format: "%.2f cores / %.2f cores", usedCores, Double(totalCores))
    }

    private func memoryUsagePercent(for snapshot: SystemSnapshot) -> String {
        guard snapshot.memoryTotalBytes > 0 else { return "—" }
        let ratio = Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes)
        return MetricsFormatter.percent(min(max(ratio * 100, 0), 100))
    }

    private func memoryUsageFootnote(for snapshot: SystemSnapshot) -> String {
        guard snapshot.memoryTotalBytes > 0 else {
            return MetricsFormatter.bytes(snapshot.memoryUsedBytes)
        }
        return "\(MetricsFormatter.bytes(snapshot.memoryUsedBytes)) / \(MetricsFormatter.bytes(snapshot.memoryTotalBytes))"
    }
}

private struct OverviewMetricCard: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
    }
}

private struct FlexibleOverviewSlotCard<Content: View>: View {
    @Binding var mode: OverviewFlexibleSlotMode
    @State private var isPickerPresented = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isPickerPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(modeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.75))
                        .offset(y: 1)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPickerPresented, attachmentAnchor: .point(.bottomLeading), arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(OverviewFlexibleSlotMode.allCases) { option in
                        Button {
                            mode = option
                            isPickerPresented = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(option.title)
                                    .font(.system(size: 14, weight: .medium))
                                Spacer(minLength: 8)
                                if option == mode {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .frame(width: 140)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
    }

    private var modeTitle: String {
        switch mode {
        case .thermal:
            return "Thermal State"
        case .weather:
            return "Weather"
        case .focus:
            return "Focus"
        case .oscarDay:
            return "Oscar's Day"
        }
    }
}

private struct ThermalStateOverviewCard: View {
    let value: String
    let statusLine: String
    let tint: String
    let sourceLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(tintColor)
                .frame(maxWidth: .infinity, alignment: .center)

            if let sourceLine {
                Text(sourceLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 10)
            }

            Spacer(minLength: 10)

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var tintColor: Color {
        switch tint {
        case "cool":
            return Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
        case "warm":
            return Color(red: 0xF5 / 255, green: 0xC4 / 255, blue: 0x51 / 255)
        case "hot":
            return Color(red: 0xF2 / 255, green: 0x8C / 255, blue: 0x38 / 255)
        case "critical":
            return Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x5F / 255)
        default:
            return .primary
        }
    }
}

private struct FocusOverviewCard: View {
    let value: String
    let footnote: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 10)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct OscarDayOverviewCard: View {
    let emoji: String
    let title: String
    let footnote: String
    let tint: Color
    let onCycle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Button(action: onCycle) {
                VStack(spacing: 0) {
                    Text(emoji)
                        .font(.system(size: 34))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: 4)

                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(tint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 10)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct OscarDayState {
    let emoji: String
    let title: String
    let tint: Color
}

private enum OscarDayStatus: CaseIterable {
    case breakfast
    case nap
    case outdoor
    case fruit

    var next: OscarDayStatus {
        switch self {
        case .breakfast:
            return .nap
        case .nap:
            return .outdoor
        case .outdoor:
            return .fruit
        case .fruit:
            return .breakfast
        }
    }
}

private struct WeatherOverviewCard: View {
    let temperature: String
    let footnote: String
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, alignment: .trailing)

                Text(temperature)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 0, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 10)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct NetworkOverviewMetricCard: View {
    static let fixedHeight: CGFloat = 128

    let title: String
    let upload: String
    let download: String
    let footnote: String

    private var uploadParts: ThroughputParts { ThroughputParts(upload) }
    private var downloadParts: ThroughputParts { ThroughputParts(download) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                throughputRow(symbol: "↑", parts: uploadParts)
                throughputRow(symbol: "↓", parts: downloadParts)
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
    }

    @ViewBuilder
    private func throughputRow(symbol: String, parts: ThroughputParts) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(symbol)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(width: 20, alignment: .leading)

            Text(parts.value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)

            Text(parts.unit)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }
}

private struct ThroughputParts {
    let value: String
    let unit: String

    init(_ raw: String) {
        let normalized = raw.replacingOccurrences(of: "/s", with: "")
        let pieces = normalized.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if pieces.count == 2 {
            let parsedValue = String(pieces[0])
            value = parsedValue.compare("zero", options: .caseInsensitive) == .orderedSame ? "0" : parsedValue
            unit = String(pieces[1]) + "/s"
        } else {
            value = normalized.compare("zero", options: .caseInsensitive) == .orderedSame ? "0" : normalized
            unit = ""
        }
    }
}

private struct OverviewPrimaryRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ThermalStateDisplay {
    let title: String
    let subtitle: String
    let color: String
}

private struct MenuBarDashboardCluster: View {
    let snapshot: SystemSnapshot
    let settings: FluxBarSettings
    let mode: ResolvedMenuBarMode

    private var isCompact: Bool { mode == .compact }

    var body: some View {
        HStack(spacing: isCompact ? 5 : 7) {
            if settings.showCPUUsage {
                MenuBarMeterGroup(
                    label: "C",
                    value: snapshot.cpuUsagePercent / 100,
                    tint: .orange
                )
            }

            if settings.showTemperature && !isCompact {
                MenuBarMeterGroup(
                    label: "G",
                    value: gpuIndicatorValue,
                    tint: .red,
                    isUnavailable: gpuIndicatorValue == nil
                )
            }

            if settings.showMemory {
                let memoryRatio = snapshot.memoryTotalBytes > 0
                    ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes)
                    : 0
                MenuBarMeterGroup(
                    label: "M",
                    value: memoryRatio,
                    tint: .blue
                )
            }

            if settings.showNetwork {
                MenuBarNetworkStack(
                    uploadText: MetricsFormatter.menuBarStackedThroughput(snapshot.uploadBytesPerSecond),
                    downloadText: MetricsFormatter.menuBarStackedThroughput(snapshot.downloadBytesPerSecond),
                    compact: isCompact
                )
            }
        }
    }

    private var gpuIndicatorValue: Double? {
        if let gpu = snapshot.temperature.gpuCelsius {
            return min(max((gpu - 35) / 55, 0), 1)
        }
        return nil
    }
}

private struct MenuBarMeterGroup: View {
    let label: String
    let value: Double?
    let tint: Color
    var isUnavailable: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            MeterTagLabel(text: label)
            VerticalMeter(value: value, tint: tint, isUnavailable: isUnavailable)
        }
        .frame(height: 18)
    }
}

private struct MeterTagLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 8)
    }
}

private struct VerticalMeter: View {
    let value: Double?
    let tint: Color
    var isUnavailable: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.primary.opacity(0.14))

            if let value {
                Capsule()
                    .fill(tint.gradient)
                    .frame(height: 3 + (11 * min(max(value, 0), 1)))
                    .padding(2)
            } else if isUnavailable {
                Capsule()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .padding(1)
            }
        }
        .frame(width: 10, height: 18)
    }
}

private struct MenuBarNetworkStack: View {
    let uploadText: String
    let downloadText: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? -1 : 0) {
            MenuBarNetworkLine(symbol: "↑", value: uploadText)
            MenuBarNetworkLine(symbol: "↓", value: downloadText)
        }
        .frame(width: compact ? 46 : 52, alignment: .leading)
        .frame(height: 18)
    }
}

private struct MenuBarNetworkLine: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.system(size: 9, weight: .bold, design: .rounded))
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)
        }
    }
}

private struct AlertBanner: View {
    let alert: FluxAlert

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.symbolName)
                .foregroundStyle(Color(nsColor: alert.level.tint.color))
                .font(.system(size: 15, weight: .bold))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    RiskBadge(level: alert.level)
                }

                Text(alert.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
    }
}

private struct TrendMetricCard: View {
    let title: String
    let value: String
    let points: [Double]
    let tint: Color
    let valueFormatter: (Double) -> String
    var emptyMessage: String = "Waiting for trend"

    private var latestValueText: String {
        guard let latest = points.last else { return emptyMessage }
        return valueFormatter(latest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(latestValueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SparklineView(points: points, tint: tint)
                .frame(height: 42)
                .overlay(alignment: .center) {
                    if points.count < 2 {
                        Text(emptyMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
    }
}

private struct SparklineView: View {
    let points: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.08))

                if points.count >= 2, let path = sparklinePath(in: geometry.size) {
                    path
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func sparklinePath(in size: CGSize) -> Path? {
        guard points.count >= 2 else { return nil }
        let minValue = points.min() ?? 0
        let maxValue = points.max() ?? 1
        let span = max(maxValue - minValue, 1)
        let stepX = size.width / CGFloat(max(points.count - 1, 1))

        var path = Path()

        for (index, point) in points.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (point - minValue) / span
            let y = size.height - (CGFloat(normalized) * (size.height - 6)) - 3

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

private struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Text(level.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(nsColor: level.tint.color))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: level.tint.color).opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct InsightList: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.callout)
            }
        }
    }
}

private struct ProcessRow: View {
    let process: TopProcess

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(process.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text(MetricsFormatter.percent(process.cpuPercent))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Label(MetricsFormatter.bytes(process.memoryBytes), systemImage: "memorychip")

                if let networkHint = process.networkHint {
                    Label(networkHint, systemImage: "arrow.up.arrow.down")
                }

                if let primaryTag = process.impactTags.first {
                    Text("• \(primaryTag)")
                        .font(.caption.weight(.semibold))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
    }

    var body: some View { bodyView }
}

private struct StatusLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.callout)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: FluxBarSettings
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        Form {
            Section("Menu Bar") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    MenuBarPreviewStrip(
                        settings: settings,
                        monitor: monitor
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Changes in this section update the preview immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Mode", selection: $settings.menuBarMode) {
                    ForEach(MenuBarModePreference.allCases.filter { $0 != .singleMetric }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Modules")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    MenuBarModulesEditor()
                        .environmentObject(settings)
                }
            }

            Section("Panel") {
                Toggle("Show Status", isOn: $settings.showStatusSection)
                Toggle("Show Top Processes", isOn: $settings.showTopProcessesSection)
                if settings.showTopProcessesSection {
                    Picker("Top Processes sort", selection: $settings.topProcessSortMode) {
                        ForEach(TopProcessSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Picker("Overview flex card", selection: $settings.overviewFlexibleSlotMode) {
                    ForEach(OverviewFlexibleSlotMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Sampling") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Text("\(settings.refreshInterval, specifier: "%.1f") s")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $settings.refreshInterval, in: 1...5, step: 0.5)
            }

            Section("Heat Analysis") {
                Toggle("Enable heating analysis", isOn: $settings.heatAnalysisEnabled)
                Toggle("Enable alert evaluation", isOn: $settings.alertsEnabled)
                Toggle("Allow notifications", isOn: $settings.notificationsEnabled)

                LabeledContent("Notification cooldown") {
                    Text("\(Int(settings.notificationCooldownMinutes)) min")
                }
                Slider(value: $settings.notificationCooldownMinutes, in: 2...60, step: 1)

                Text(settings.notificationsStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("High CPU threshold") {
                    Text("\(Int(settings.cpuHighUsageThreshold))%")
                }
                Slider(value: $settings.cpuHighUsageThreshold, in: 40...95, step: 1)

                LabeledContent("High memory threshold") {
                    Text("\(Int(settings.memoryHighWatermark * 100))%")
                }
                Slider(value: $settings.memoryHighWatermark, in: 0.55...0.95, step: 0.01)

                LabeledContent("High network threshold") {
                    Text("\(settings.networkHighWatermarkMBps, specifier: "%.1f") MB/s")
                }
                Slider(value: $settings.networkHighWatermarkMBps, in: 1...40, step: 0.5)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
                Text(settings.launchAtLoginMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Maintenance") {
                Button("Reset Stable Defaults") {
                    settings.resetToStableDefaults()
                }

                Text("Resets FluxBar to the recommended self-use baseline without touching launch-at-login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct MenuBarPreviewStrip: View {
    let settings: FluxBarSettings
    let monitor: SystemMonitor

    var body: some View {
        StatusBarPreviewRepresentable(
            settings: settings,
            monitor: monitor
        )
        .frame(maxWidth: .infinity, minHeight: 102, maxHeight: 102)
    }
}

private struct MenuBarModulesEditor: View {
    @EnvironmentObject private var settings: FluxBarSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarPinnedModuleRow(module: .temperature)

            Divider()
                .padding(.leading, 28)

            List {
                ForEach(settings.movableMenuBarModules) { module in
                    MenuBarSortableModuleRow(module: module)
                        .environmentObject(settings)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: settings.moveMovableMenuBarModules)
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(settings.movableMenuBarModules.count) * 34 + 6)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

private struct MenuBarPinnedModuleRow: View {
    let module: MenuBarModule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                Text("Always shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct MenuBarSortableModuleRow: View {
    @EnvironmentObject private var settings: FluxBarSettings

    let module: MenuBarModule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(module.title)
                .font(.callout)

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.isMenuBarModuleVisible(module) },
                set: { settings.setMenuBarModuleVisibility(module, isVisible: $0) }
            ))
            .labelsHidden()
            .controlSize(.mini)
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct MenuBarPresentation {
    let mode: ResolvedMenuBarMode
    let symbolName: String
    let label: String?
    let fixedWidth: CGFloat
    let helpText: String
}

@MainActor
enum MenuBarPresentationEngine {
    static func makePresentation(
        snapshot: SystemSnapshot?,
        assessment: HeatAssessment,
        settings: FluxBarSettings
    ) -> MenuBarPresentation {
        guard let snapshot else {
            return MenuBarPresentation(
                mode: .icon,
                symbolName: "waveform.path.ecg",
                label: "Loading",
                fixedWidth: fixedWidth(for: .icon),
                helpText: "FluxBar is collecting its first samples."
            )
        }

        let preferredModes: [ResolvedMenuBarMode]
        switch settings.menuBarMode {
        case .automatic:
            preferredModes = [.standard, .compact, .icon]
        case .standard:
            preferredModes = [.standard]
        case .compact:
            preferredModes = [.compact]
        case .icon:
            preferredModes = [.icon]
        case .singleMetric:
            preferredModes = [.compact]
        }

        let budget = statusWidthBudget()

        for mode in preferredModes {
            let label = labelText(for: mode, snapshot: snapshot, settings: settings)
            if settings.menuBarMode != .automatic || estimatedWidth(for: label, mode: mode) <= budget {
                return MenuBarPresentation(
                    mode: mode,
                    symbolName: symbol(for: assessment, mode: mode, preferredSingleMetric: settings.preferredSingleMetric),
                    label: label,
                    fixedWidth: fixedWidth(for: mode),
                    helpText: helpText(snapshot: snapshot, assessment: assessment, mode: mode, budget: budget)
                )
            }
        }

        return MenuBarPresentation(
            mode: .singleMetric,
            symbolName: symbol(for: assessment, mode: .singleMetric, preferredSingleMetric: settings.preferredSingleMetric),
            label: labelText(for: .singleMetric, snapshot: snapshot, settings: settings),
            fixedWidth: fixedWidth(for: .singleMetric),
            helpText: helpText(snapshot: snapshot, assessment: assessment, mode: .singleMetric, budget: budget)
        )
    }

    private static func symbol(
        for assessment: HeatAssessment,
        mode: ResolvedMenuBarMode,
        preferredSingleMetric: SingleMetricKind
    ) -> String {
        if mode == .icon {
            return "gauge.with.dots.needle.33percent"
        }
        if mode == .singleMetric {
            switch preferredSingleMetric {
            case .temperature:
                return "thermometer.medium"
            case .network:
                return "arrow.up.arrow.down"
            case .memory:
                return "memorychip"
            case .cpu:
                return "cpu"
            }
        }
        return "thermometer.medium"
    }

    private static func labelText(
        for mode: ResolvedMenuBarMode,
        snapshot: SystemSnapshot,
        settings: FluxBarSettings
    ) -> String? {
        switch mode {
        case .standard:
            return standardLabel(snapshot: snapshot, settings: settings)
        case .compact:
            return compactLabel(snapshot: snapshot, settings: settings)
        case .icon:
            return iconLabel(snapshot: snapshot, settings: settings)
        case .singleMetric:
            return singleMetricLabel(snapshot: snapshot, preferred: settings.preferredSingleMetric)
        }
    }

    private static func standardLabel(snapshot: SystemSnapshot, settings: FluxBarSettings) -> String {
        var segments: [String] = []

        if settings.showTemperature {
            segments.append(menuBarTemperatureLabel(snapshot))
        }
        if settings.showNetwork {
            segments.append(networkPairLabel(snapshot))
        }
        if settings.showMemory {
            segments.append("MEM \(MetricsFormatter.bytes(snapshot.memoryUsedBytes))")
        }
        if settings.showCPUUsage {
            segments.append("CPU \(MetricsFormatter.percent(snapshot.cpuUsagePercent))")
        }

        return segments.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func compactLabel(snapshot: SystemSnapshot, settings: FluxBarSettings) -> String {
        var segments: [String] = []

        if settings.showTemperature {
            segments.append(menuBarTemperatureLabel(snapshot))
        }
        if settings.showNetwork {
            segments.append(compactNetworkPairLabel(snapshot))
        }
        if settings.showMemory {
            segments.append(MetricsFormatter.compactBytes(snapshot.memoryUsedBytes))
        }
        if settings.showCPUUsage {
            segments.append(MetricsFormatter.percent(snapshot.cpuUsagePercent))
        }

        return segments.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func iconLabel(snapshot: SystemSnapshot, settings: FluxBarSettings) -> String {
        var chunks: [String] = []

        if settings.showNetwork {
            chunks.append(compactNetworkPairLabel(snapshot))
        }
        if settings.showMemory {
            chunks.append("⌂\(MetricsFormatter.compactBytes(snapshot.memoryUsedBytes))")
        }
        if settings.showCPUUsage {
            chunks.append("⚙︎\(Int(snapshot.cpuUsagePercent.rounded()))")
        }

        return chunks.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func singleMetricLabel(snapshot: SystemSnapshot, preferred: SingleMetricKind) -> String {
        let orderedKinds = [preferred] + SingleMetricKind.allCases.filter { $0 != preferred }

        for kind in orderedKinds {
            switch kind {
            case .temperature:
                if let temperature = snapshot.temperature.cpuCelsius ?? snapshot.temperature.gpuCelsius {
                    return MetricsFormatter.temperature(temperature)
                }
                return menuBarThermalFallback(snapshot.thermalState)
            case .network:
                return compactNetworkPairLabel(snapshot)
            case .memory:
                return MetricsFormatter.compactBytes(snapshot.memoryUsedBytes)
            case .cpu:
                return MetricsFormatter.percent(snapshot.cpuUsagePercent)
            }
        }

        return "FluxBar"
    }

    private static func primaryTemperatureLabel(_ snapshot: SystemSnapshot) -> String {
        if let cpu = snapshot.temperature.cpuCelsius {
            return MetricsFormatter.temperature(cpu)
        }
        if let gpu = snapshot.temperature.gpuCelsius {
            return MetricsFormatter.temperature(gpu)
        }
        return snapshot.thermalState.title.uppercased()
    }

    private static func menuBarTemperatureLabel(_ snapshot: SystemSnapshot) -> String {
        if let cpu = snapshot.temperature.cpuCelsius {
            return MetricsFormatter.temperature(cpu)
        }
        if let gpu = snapshot.temperature.gpuCelsius {
            return MetricsFormatter.temperature(gpu)
        }
        return ""
    }

    private static func menuBarThermalFallback(_ state: ThermalStateDescriptor) -> String {
        switch state {
        case .nominal:
            return "OK"
        case .fair:
            return "WARM"
        case .serious:
            return "HOT"
        case .critical:
            return "CRIT"
        }
    }

    private static func networkPairLabel(_ snapshot: SystemSnapshot) -> String {
        "↑\(MetricsFormatter.menuBarThroughput(snapshot.uploadBytesPerSecond)) ↓\(MetricsFormatter.menuBarThroughput(snapshot.downloadBytesPerSecond))"
    }

    private static func compactNetworkPairLabel(_ snapshot: SystemSnapshot) -> String {
        "↑\(MetricsFormatter.menuBarThroughput(snapshot.uploadBytesPerSecond)) ↓\(MetricsFormatter.menuBarThroughput(snapshot.downloadBytesPerSecond))"
    }

    private static func fixedWidth(for mode: ResolvedMenuBarMode) -> CGFloat {
        switch mode {
        case .standard:
            return 178
        case .compact:
            return 166
        case .icon:
            return 160
        case .singleMetric:
            return 92
        }
    }

    private static func statusWidthBudget() -> CGFloat {
        // FluxBar targets a single notch MacBook Air configuration, so a stable
        // fixed budget is safer than querying menu bar presentation state during launch.
        188
    }

    private static func estimatedWidth(for text: String?, mode: ResolvedMenuBarMode) -> CGFloat {
        if mode == .standard || mode == .compact {
            return fixedWidth(for: mode)
        }
        guard let text else { return 28 }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        ]
        let width = NSString(string: text).size(withAttributes: attributes).width
        let iconPadding: CGFloat = mode == .icon ? 18 : 24
        return width + iconPadding
    }

    private static func helpText(
        snapshot: SystemSnapshot,
        assessment: HeatAssessment,
        mode: ResolvedMenuBarMode,
        budget: CGFloat
    ) -> String {
        "Mode: \(mode.rawValue). Notch-aware width budget: \(Int(budget)) pt. Current heat risk: \(assessment.riskLevel.title). Thermal state: \(snapshot.thermalState.title)."
    }
}

enum MetricsFormatter {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func bytes(_ value: UInt64) -> String {
        formattedBytes(Double(value))
    }

    static func compactBytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 1 {
            return "\(Int(gb.rounded()))G"
        }
        let mb = Double(value) / 1_048_576
        return "\(Int(mb.rounded()))M"
    }

    static func memoryUsagePair(used: UInt64, total: UInt64) -> String {
        guard total > 0 else { return bytes(used) }

        let unitLabel: String
        let divisor: Double

        if total >= 1_073_741_824 {
            unitLabel = "GB"
            divisor = 1_073_741_824
        } else if total >= 1_048_576 {
            unitLabel = "MB"
            divisor = 1_048_576
        } else {
            unitLabel = "KB"
            divisor = 1024
        }

        let usedValue = Double(used) / divisor
        let totalValue = Double(total) / divisor
        return "\(formattedCompact(usedValue))/\(formattedCompact(totalValue)) \(unitLabel)"
    }

    static func throughput(_ bytesPerSecond: Double) -> String {
        formattedBytes(bytesPerSecond) + "/s"
    }

    static func compactThroughput(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond / 1_048_576
        if mbps >= 1 {
            return String(format: "%.1fM", mbps)
        }
        let kbps = bytesPerSecond / 1024
        return String(format: "%.0fK", kbps)
    }

    static func menuBarThroughput(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond / 1_048_576
        let raw: String

        if mbps >= 10 {
            raw = "\(Int(mbps.rounded()))M"
        } else if mbps >= 1 {
            raw = String(format: "%.1fM", mbps)
        } else {
            let kbps = max(bytesPerSecond / 1024, 0)
            raw = "\(Int(kbps.rounded()))K"
        }

        return raw.leftPadded(to: 4)
    }

    static func menuBarStackedThroughput(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond / 1_048_576
        if mbps >= 10 {
            return "\(Int(mbps.rounded()))MB/s"
        }
        if mbps >= 1 {
            return String(format: "%.1fMB/s", mbps)
        }

        let kbps = max(bytesPerSecond / 1024, 0)
        return "\(Int(kbps.rounded()))KB/s"
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    static func temperature(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func temperatureWithUnit(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°C"
    }

    static func temperatureWithUnit(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }


    private static func formattedBytes(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(value))
    }

    private static func formattedCompact(_ value: Double) -> String {
        if value >= 100 {
            return "\(Int(value.rounded()))"
        }
        let oneDecimal = (value * 10).rounded() / 10
        if oneDecimal.rounded() == oneDecimal {
            return "\(Int(oneDecimal))"
        }
        return String(format: "%.1f", oneDecimal)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        guard count < length else { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
