import AppKit
import Combine
import Darwin
import Foundation
import UserNotifications

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var latestSnapshot: SystemSnapshot?
    @Published private(set) var latestAssessment: HeatAssessment = .unavailable
    @Published private(set) var history: [SystemSnapshot] = []
    @Published private(set) var activeAlerts: [FluxAlert] = []

    private let settings: FluxBarSettings
    private let sampler = SystemSampler()
    private let analyzer = HeatAnalyzer()
    private let alertCoordinator = AlertCoordinator()
    private let historyStore = HistoryStore()
    private var refreshTask: Task<Void, Never>?
    private var lastPersistedAt = Date.distantPast
    private var settingsCancellables: Set<AnyCancellable> = []
    private var terminationObserver: NSObjectProtocol?
    private var refreshInFlight = false
    private var pendingRefresh = false

    init(settings: FluxBarSettings) {
        self.settings = settings
        bindSettings()
        registerTerminationObserver()
        Task { [weak self] in
            guard let self else { return }
            let restoredHistory = await historyStore.loadHistory()
            await MainActor.run {
                self.history = restoredHistory
                self.latestSnapshot = restoredHistory.last
                self.refreshDerivedState(using: settings.monitoringConfiguration)
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func startIfNeeded() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow()

            while !Task.isCancelled {
                let interval = UInt64(max(settings.refreshInterval, 1.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: interval)
                await self.refreshNow()
            }
        }
    }

    func refreshNow() async {
        if refreshInFlight {
            pendingRefresh = true
            return
        }

        refreshInFlight = true
        defer { refreshInFlight = false }

        repeat {
            pendingRefresh = false
            await runRefreshCycle()
        } while pendingRefresh
    }

    private func runRefreshCycle() async {
        let config = settings.monitoringConfiguration
        let snapshot = await Task.detached(priority: .utility) { [sampler] in
            sampler.sample(configuration: config)
        }.value

        latestSnapshot = snapshot
        history.append(snapshot)
        pruneHistory()
        let persistedHistory = history

        refreshDerivedState(using: config)

        if snapshot.timestamp.timeIntervalSince(lastPersistedAt) >= 15 {
            lastPersistedAt = snapshot.timestamp
            Task.detached(priority: .utility) { [historyStore] in
                await historyStore.save(history: persistedHistory)
            }
        }
    }

    func clearHistory() {
        history = latestSnapshot.map { [$0] } ?? []
        alertCoordinator.reset()
        persistHistoryNow()
        refreshDerivedState(using: settings.monitoringConfiguration)
    }

    func persistHistoryNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        HistoryPersistence.save(
            history: history,
            encoder: encoder,
            retentionWindow: 30 * 60
        )
        lastPersistedAt = latestSnapshot?.timestamp ?? Date()
    }

    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-30 * 60)
        history.removeAll { $0.timestamp < cutoff }
    }

    private func refreshDerivedState(using configuration: MonitoringConfiguration) {
        guard let snapshot = latestSnapshot else {
            latestAssessment = .unavailable
            activeAlerts = []
            return
        }

        if configuration.heatAnalysisEnabled {
            latestAssessment = analyzer.analyze(
                snapshot: snapshot,
                history: history,
                configuration: configuration
            )
        } else {
            latestAssessment = .unavailable
        }

        activeAlerts = alertCoordinator.evaluate(
            snapshot: snapshot,
            assessment: latestAssessment,
            configuration: configuration
        )
    }

    private func bindSettings() {
        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartSamplingLoop()
            }
            .store(in: &settingsCancellables)

        Publishers.MergeMany(
            settings.$topProcessSortMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$heatAnalysisEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$cpuHighUsageThreshold.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$memoryHighWatermark.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$networkHighWatermarkMBps.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$alertsEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$notificationsEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$notificationCooldownMinutes.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            self?.applyConfigurationChange()
        }
        .store(in: &settingsCancellables)
    }

    private func registerTerminationObserver() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistHistoryNow()
            }
        }
    }

    private func restartSamplingLoop() {
        refreshTask?.cancel()
        refreshTask = nil
        startIfNeeded()
    }

    private func applyConfigurationChange() {
        if !settings.alertsEnabled {
            alertCoordinator.reset()
            activeAlerts = []
        }

        if let latestSnapshot {
            let sortedProcesses = Self.sortProcesses(
                latestSnapshot.topProcesses,
                by: settings.topProcessSortMode
            )
            if sortedProcesses != latestSnapshot.topProcesses {
                self.latestSnapshot = latestSnapshot.updating(topProcesses: sortedProcesses)
            }
        }

        refreshDerivedState(using: settings.monitoringConfiguration)
    }

    private static func sortProcesses(_ processes: [TopProcess], by sortMode: TopProcessSortMode) -> [TopProcess] {
        processes.sorted { lhs, rhs in
            switch sortMode {
            case .heatingImpact:
                if lhs.heatingScore == rhs.heatingScore {
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                return lhs.heatingScore > rhs.heatingScore
            case .cpu:
                if lhs.cpuPercent == rhs.cpuPercent {
                    return lhs.heatingScore > rhs.heatingScore
                }
                return lhs.cpuPercent > rhs.cpuPercent
            case .memory:
                if lhs.memoryBytes == rhs.memoryBytes {
                    return lhs.heatingScore > rhs.heatingScore
                }
                return lhs.memoryBytes > rhs.memoryBytes
            }
        }
    }
}

final class SystemSampler: @unchecked Sendable {
    private let cpuReader = CPUUsageReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkRateReader()
    private let processReader = TopProcessReader()
    private let temperatureReader = TemperatureReader()
    private let processInfo = ProcessInfo.processInfo

    private var lastProcesses: [TopProcess] = []
    private var lastTemperature = TemperatureSnapshot.unavailable(reason: "Sensor probe pending")
    private var lastProcessRefresh = Date.distantPast
    private var lastTemperatureRefresh = Date.distantPast
    private var nextTemperatureProbeInterval: TimeInterval = 20

    func sample(configuration: MonitoringConfiguration) -> SystemSnapshot {
        let now = Date()
        let cpuUsage = cpuReader.readCPUUsagePercent()
        let memory = memoryReader.readMemory()
        let network = networkReader.readRates()

        if now.timeIntervalSince(lastProcessRefresh) >= max(configuration.refreshInterval * 3, 6) {
            lastProcesses = processReader.readTopProcesses(
                memoryTotal: memory.totalBytes,
                sortMode: configuration.topProcessSortMode
            )
            lastProcessRefresh = now
        }

        if now.timeIntervalSince(lastTemperatureRefresh) >= nextTemperatureProbeInterval {
            lastTemperature = temperatureReader.readTemperature()
            lastTemperatureRefresh = now
            nextTemperatureProbeInterval = lastTemperature.isAvailable ? 20 : 120
            if !lastTemperature.isAvailable,
               !lastTemperature.sourceDescription.contains("retrying less frequently") {
                lastTemperature.sourceDescription += " FluxBar is retrying less frequently."
            }
        }

        return SystemSnapshot(
            timestamp: now,
            cpuUsagePercent: cpuUsage,
            memoryUsedBytes: memory.usedBytes,
            memoryTotalBytes: memory.totalBytes,
            swapUsedBytes: memory.swapUsedBytes,
            memoryPressure: memory.pressure,
            downloadBytesPerSecond: network.downloadBytesPerSecond,
            uploadBytesPerSecond: network.uploadBytesPerSecond,
            temperature: lastTemperature,
            thermalState: ThermalStateDescriptor(processInfo.thermalState),
            topProcesses: lastProcesses
        )
    }
}

private struct MemorySample {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let swapUsedBytes: UInt64
    let pressure: MemoryPressureLevel
}

private struct NetworkSample {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

private final class CPUUsageReader: @unchecked Sendable {
    private var lastInfo: host_cpu_load_info = host_cpu_load_info()
    private var hasBaseline = false

    func readCPUUsagePercent() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        defer {
            lastInfo = info
            hasBaseline = true
        }

        guard hasBaseline else { return 0 }

        let user = Double(info.cpu_ticks.0 - lastInfo.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 - lastInfo.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 - lastInfo.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 - lastInfo.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return ((user + system + nice) / total) * 100
    }
}

private final class MemoryReader: @unchecked Sendable {
    func readMemory() -> MemorySample {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64()

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemorySample(usedBytes: 0, totalBytes: total, swapUsedBytes: 0, pressure: .normal)
        }

        let pageSizeBytes = UInt64(pageSize)
        let active = UInt64(stats.active_count) * pageSizeBytes
        let wired = UInt64(stats.wire_count) * pageSizeBytes
        let compressed = UInt64(stats.compressor_page_count) * pageSizeBytes
        let used = active + wired + compressed
        let swap = swapUsageBytes()
        let ratio = total > 0 ? Double(used) / Double(total) : 0
        let pressure: MemoryPressureLevel

        if ratio >= 0.85 || swap > 512 * 1_048_576 {
            pressure = .high
        } else if ratio >= 0.72 || swap > 0 {
            pressure = .elevated
        } else {
            pressure = .normal
        }

        return MemorySample(
            usedBytes: min(used, total),
            totalBytes: total,
            swapUsedBytes: swap,
            pressure: pressure
        )
    }

    private func swapUsageBytes() -> UInt64 {
        var size = MemoryLayout<xsw_usage>.stride
        var usage = xsw_usage()
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return 0 }
        return usage.xsu_used
    }
}

private final class NetworkRateReader: @unchecked Sendable {
    private var previousInputBytes: UInt64 = 0
    private var previousOutputBytes: UInt64 = 0
    private var previousTimestamp = Date.distantPast
    private var hasBaseline = false

    func readRates() -> NetworkSample {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else {
            return NetworkSample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        defer { freeifaddrs(addrs) }

        var totalInput: UInt64 = 0
        var totalOutput: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }

            let flags = Int32(entry.ifa_flags)
            let name = String(cString: entry.ifa_name)

            guard (flags & IFF_UP) != 0,
                  (flags & IFF_RUNNING) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw") else {
                continue
            }

            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                continue
            }

            totalInput += UInt64(data.ifi_ibytes)
            totalOutput += UInt64(data.ifi_obytes)
        }

        let now = Date()
        defer {
            previousInputBytes = totalInput
            previousOutputBytes = totalOutput
            previousTimestamp = now
            hasBaseline = true
        }

        guard hasBaseline else {
            return NetworkSample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        let elapsed = now.timeIntervalSince(previousTimestamp)
        guard elapsed > 0 else {
            return NetworkSample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        guard let download = validatedRate(
            currentBytes: totalInput,
            previousBytes: previousInputBytes,
            elapsed: elapsed
        ), let upload = validatedRate(
            currentBytes: totalOutput,
            previousBytes: previousOutputBytes,
            elapsed: elapsed
        ) else {
            previousInputBytes = totalInput
            previousOutputBytes = totalOutput
            previousTimestamp = now
            hasBaseline = true
            return NetworkSample(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        return NetworkSample(downloadBytesPerSecond: download, uploadBytesPerSecond: upload)
    }

    private func validatedRate(
        currentBytes: UInt64,
        previousBytes: UInt64,
        elapsed: TimeInterval
    ) -> Double? {
        // if_data byte counters are 32-bit on this path and can wrap or reset.
        guard currentBytes >= previousBytes else {
            return nil
        }

        let delta = Double(currentBytes - previousBytes)
        let rate = delta / elapsed

        // Discard clearly implausible bursts caused by counter resets.
        let plausibleUpperBound = 100 * 1_073_741_824.0
        guard rate.isFinite, rate >= 0, rate <= plausibleUpperBound else {
            return nil
        }

        return rate
    }
}

private final class TopProcessReader: @unchecked Sendable {
    func readTopProcesses(memoryTotal: UInt64, sortMode: TopProcessSortMode) -> [TopProcess] {
        let result = CommandRunner.run(
            executable: "/bin/ps",
            arguments: ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"],
            timeout: 1.5
        )

        guard result.exitCode == 0 else { return [] }

        let processes = result.standardOutput
            .split(separator: "\n")
            .compactMap { line in parseProcessLine(String(line), memoryTotal: memoryTotal) }
            .filter { $0.cpuPercent > 0.1 || $0.memoryBytes > 50 * 1_048_576 }

        return processes
            .sorted { lhs, rhs in
                switch sortMode {
                case .heatingImpact:
                    if lhs.heatingScore == rhs.heatingScore {
                        return lhs.cpuPercent > rhs.cpuPercent
                    }
                    return lhs.heatingScore > rhs.heatingScore
                case .cpu:
                    if lhs.cpuPercent == rhs.cpuPercent {
                        return lhs.heatingScore > rhs.heatingScore
                    }
                    return lhs.cpuPercent > rhs.cpuPercent
                case .memory:
                    if lhs.memoryBytes == rhs.memoryBytes {
                        return lhs.heatingScore > rhs.heatingScore
                    }
                    return lhs.memoryBytes > rhs.memoryBytes
                }
            }
            .prefix(6)
            .map { $0 }
    }

    private func parseProcessLine(_ line: String, memoryTotal: UInt64) -> TopProcess? {
        let components = line.split(
            separator: " ",
            maxSplits: 3,
            omittingEmptySubsequences: true
        )

        guard components.count == 4 else {
            return nil
        }

        let pidText = String(components[0])
        let cpuText = String(components[1])
        let rssText = String(components[2])

        guard let pid = Int32(pidText),
              let cpu = Double(cpuText),
              let rssKiB = UInt64(rssText) else {
            return nil
        }

        let command = String(components[3])
        let name = URL(fileURLWithPath: command).lastPathComponent
        let memoryBytes = rssKiB * 1024
        let memoryRatio = memoryTotal > 0 ? Double(memoryBytes) / Double(memoryTotal) : 0
        let score = (cpu * 0.7) + (memoryRatio * 100 * 0.3)
        var tags: [String] = []

        if cpu >= 35 { tags.append("High CPU") }
        if memoryRatio >= 0.08 || memoryBytes >= 2 * 1_073_741_824 {
            tags.append("High Memory")
        }
        if score >= 35 {
            tags.append("Likely Heating Source")
        }

        return TopProcess(
            id: pid,
            pid: pid,
            name: name.isEmpty ? command : name,
            command: command,
            cpuPercent: cpu,
            memoryBytes: memoryBytes,
            networkHint: nil,
            impactTags: tags,
            heatingScore: score
        )
    }
}

private final class TemperatureReader: @unchecked Sendable {
    private let cacheURL = URL(fileURLWithPath: "/Users/Shared/FluxBar/thermal-cache.json")
    private let cacheMaxAge: TimeInterval = 90
    private let macmonPaths: [String]

    init() {
        macmonPaths = [
            "\(NSHomeDirectory())/.local/bin/macmon",
            "/opt/homebrew/bin/macmon",
            "/usr/local/bin/macmon"
        ]
    }

    func readTemperature() -> TemperatureSnapshot {
        let macmonAttempt = readMacmonTemperature()
        if let macmonSnapshot = macmonAttempt.snapshot {
            return macmonSnapshot
        }

        let macmonSuffix = macmonAttempt.error.map { " macmon unavailable: \($0)" } ?? ""

        if var cached = readCachedTemperature() {
            if !macmonSuffix.isEmpty {
                cached.sourceDescription += macmonSuffix
            }
            return cached
        }

        if var batterySnapshot = readBatteryTemperature() {
            if !macmonSuffix.isEmpty {
                batterySnapshot.sourceDescription += macmonSuffix
            }
            return batterySnapshot
        }

        let result = CommandRunner.run(
            executable: "/usr/bin/powermetrics",
            arguments: ["--samplers", "thermal,smc", "-n", "1"],
            timeout: 2.5
        )

        guard result.exitCode == 0 else {
            let reason = result.standardError.isEmpty ? "Temperature sensors unavailable without elevated privileges." : result.standardError
            return .unavailable(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let text = result.standardOutput
        var cpu = firstTemperature(in: text, labels: ["CPU", "P-Cluster", "E-Cluster", "package", "SoC", "die", "ANE"])
        let gpu = firstTemperature(in: text, labels: ["GPU", "GFX"])

        // On some machines powermetrics may not expose explicit CPU/GPU labels.
        if cpu == nil, gpu == nil {
            cpu = firstAnyTemperature(in: text, keywords: ["thermal", "temp", "die"])
        }

        guard cpu != nil || gpu != nil else {
            return .unavailable(reason: "powermetrics did not expose CPU/GPU die temperature on this run.")
        }

        var snapshot = TemperatureSnapshot(
            cpuCelsius: cpu,
            gpuCelsius: gpu,
            sourceDescription: "powermetrics thermal+smc sampler",
            isAvailable: true
        )
        if !macmonSuffix.isEmpty {
            snapshot.sourceDescription += macmonSuffix
        }
        return snapshot
    }

    private func readMacmonTemperature() -> (snapshot: TemperatureSnapshot?, error: String?) {
        guard let executable = macmonPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return (nil, nil)
        }

        let result = CommandRunner.run(
            executable: executable,
            arguments: ["pipe", "-s", "1", "-i", "250"],
            timeout: 2.5
        )

        guard result.exitCode == 0,
              let data = result.standardOutput.data(using: .utf8),
              let payload = parseMacmonTemperatures(data: data),
              payload.cpu != nil || payload.gpu != nil else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return (nil, "returned no CPU/GPU temperature fields")
            }
            return (nil, detail)
        }

        return (
            TemperatureSnapshot(
                cpuCelsius: payload.cpu,
                gpuCelsius: payload.gpu,
                sourceDescription: "macmon",
                isAvailable: true
            ),
            nil
        )
    }

    private func parseMacmonTemperatures(data: Data) -> (cpu: Double?, gpu: Double?)? {
        if let known = try? JSONDecoder().decode(MacmonTemperaturePayload.self, from: data),
           known.temp.cpuTempAvg != nil || known.temp.gpuTempAvg != nil {
            return (known.temp.cpuTempAvg, known.temp.gpuTempAvg)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let values = flattenedNumericValues(from: object)
        if values.isEmpty { return nil }

        let cpuCandidates = [
            "cpu_temp_avg", "cpu_temp", "cpu", "cpu_die_temp", "soc_cpu_temp"
        ]
        let gpuCandidates = [
            "gpu_temp_avg", "gpu_temp", "gpu", "gpu_die_temp", "soc_gpu_temp", "gfx_temp"
        ]

        let cpu = firstNumericValue(in: values, matchingAny: cpuCandidates)
        let gpu = firstNumericValue(in: values, matchingAny: gpuCandidates)
        return (cpu, gpu)
    }

    private func flattenedNumericValues(from object: Any, path: String = "") -> [(path: String, value: Double)] {
        if let number = object as? NSNumber {
            let value = number.doubleValue
            // Temperature sanity range in Celsius
            if value >= 15, value <= 130 {
                return [(path.lowercased(), value)]
            }
            return []
        }

        if let dict = object as? [String: Any] {
            return dict.flatMap { key, value in
                let next = path.isEmpty ? key : "\(path).\(key)"
                return flattenedNumericValues(from: value, path: next)
            }
        }

        if let array = object as? [Any] {
            return array.enumerated().flatMap { index, value in
                let next = path.isEmpty ? "[\(index)]" : "\(path)[\(index)]"
                return flattenedNumericValues(from: value, path: next)
            }
        }

        return []
    }

    private func firstNumericValue(
        in values: [(path: String, value: Double)],
        matchingAny keywords: [String]
    ) -> Double? {
        for keyword in keywords {
            if let value = values.first(where: { $0.path.contains(keyword) })?.value {
                return value
            }
        }
        return nil
    }

    private func readCachedTemperature() -> TemperatureSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(CachedTemperaturePayload.self, from: data) else {
            return nil
        }

        let age = Date().timeIntervalSince1970 - payload.timestamp
        guard age >= 0, age <= cacheMaxAge else { return nil }
        guard payload.cpuCelsius != nil || payload.gpuCelsius != nil else { return nil }

        return TemperatureSnapshot(
            cpuCelsius: payload.cpuCelsius,
            gpuCelsius: payload.gpuCelsius,
            sourceDescription: payload.source,
            isAvailable: true
        )
    }

    private func readBatteryTemperature() -> TemperatureSnapshot? {
        let result = CommandRunner.run(
            executable: "/usr/sbin/ioreg",
            arguments: ["-rn", "AppleSmartBattery", "-l"],
            timeout: 1.5
        )

        guard result.exitCode == 0 else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "\"Temperature\"\\s*=\\s*([0-9]+)"),
              let range = Range(NSRange(result.standardOutput.startIndex..<result.standardOutput.endIndex, in: result.standardOutput), in: result.standardOutput),
              let match = regex.firstMatch(in: result.standardOutput, range: NSRange(range, in: result.standardOutput)),
              let rawRange = Range(match.range(at: 1), in: result.standardOutput),
              let rawValue = Double(result.standardOutput[rawRange]) else {
            return nil
        }

        // AppleSmartBattery Temperature is in 0.1 Kelvin units.
        let celsius = (rawValue / 10.0) - 273.15
        guard celsius >= -20, celsius <= 130 else { return nil }

        return TemperatureSnapshot(
            cpuCelsius: celsius,
            gpuCelsius: nil,
            sourceDescription: "AppleSmartBattery (battery temp proxy)",
            isAvailable: true
        )
    }

    private func firstTemperature(in text: String, labels: [String]) -> Double? {
        let patterns = labels.map { label in
            "\(label)[^\\n]*?([0-9]+(?:\\.[0-9]+)?)(?:\\s*(?:°|deg)?\\s*[Cc]|\\s*℃|\\s*摄氏(?:度)?)?"
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let valueRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            guard let value = Double(text[valueRange]), value >= 15, value <= 130 else {
                continue
            }
            return value
        }

        return nil
    }

    private func firstAnyTemperature(in text: String, keywords: [String]) -> Double? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            let lowercased = line.lowercased()
            guard keywords.contains(where: { lowercased.contains($0.lowercased()) }) else {
                continue
            }
            guard let regex = try? NSRegularExpression(
                pattern: "([0-9]+(?:\\.[0-9]+)?)(?:\\s*(?:°|deg)?\\s*[Cc]|\\s*℃|\\s*摄氏(?:度)?)?"
            ) else {
                continue
            }
            let source = String(line)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            guard let match = regex.firstMatch(in: source, range: range),
                  let valueRange = Range(match.range(at: 1), in: source),
                  let value = Double(source[valueRange]) else {
                continue
            }
            guard value >= 15, value <= 130 else { continue }
            return value
        }

        return nil
    }
}

private struct CachedTemperaturePayload: Decodable {
    let timestamp: TimeInterval
    let cpuCelsius: Double?
    let gpuCelsius: Double?
    let source: String
}

private struct MacmonTemperaturePayload: Decodable {
    let temp: TemperatureValues

    struct TemperatureValues: Decodable {
        let cpuTempAvg: Double?
        let gpuTempAvg: Double?

        private enum CodingKeys: String, CodingKey {
            case cpuTempAvg = "cpu_temp_avg"
            case gpuTempAvg = "gpu_temp_avg"
        }
    }
}

@MainActor
private final class AlertCoordinator {
    private var consecutiveHits: [String: Int] = [:]
    private var lastNotificationAt: [String: Date] = [:]

    func reset() {
        consecutiveHits = [:]
        lastNotificationAt = [:]
    }

    func evaluate(
        snapshot: SystemSnapshot,
        assessment: HeatAssessment,
        configuration: MonitoringConfiguration
    ) -> [FluxAlert] {
        guard configuration.alertsEnabled else {
            reset()
            return []
        }

        let candidates = candidateAlerts(snapshot: snapshot, assessment: assessment, configuration: configuration)
        let candidateIDs = Set(candidates.map(\.id))

        consecutiveHits = consecutiveHits.filter { candidateIDs.contains($0.key) }

        for alert in candidates {
            consecutiveHits[alert.id, default: 0] += 1
        }

        let active = candidates.filter { consecutiveHits[$0.id, default: 0] >= 2 }

        if configuration.notificationsEnabled && NotificationSupport.isAvailableInCurrentRunMode {
            for alert in active {
                maybeSendNotification(for: alert, cooldown: configuration.notificationCooldown)
            }
        }

        return active
    }

    private func candidateAlerts(
        snapshot: SystemSnapshot,
        assessment: HeatAssessment,
        configuration: MonitoringConfiguration
    ) -> [FluxAlert] {
        var alerts: [FluxAlert] = []

        if assessment.riskLevel == .high || assessment.riskLevel == .critical {
            alerts.append(
                FluxAlert(
                    id: "heat-risk-\(assessment.riskLevel.rawValue)",
                    level: assessment.riskLevel,
                    title: "Heat Risk \(assessment.riskLevel.title)",
                    message: assessment.explanation,
                    symbolName: assessment.riskLevel == .critical ? "flame.fill" : "exclamationmark.thermometer"
                )
            )
        }

        if snapshot.thermalState == .serious || snapshot.thermalState == .critical {
            alerts.append(
                FluxAlert(
                    id: "thermal-\(snapshot.thermalState.rawValue)",
                    level: snapshot.thermalState == .critical ? .critical : .high,
                    title: "Thermal State \(snapshot.thermalState.title)",
                    message: "macOS thermal pressure is already elevated. Reducing load now is recommended.",
                    symbolName: "thermometer.high"
                )
            )
        }

        if snapshot.cpuUsagePercent >= configuration.cpuHighUsageThreshold {
            alerts.append(
                FluxAlert(
                    id: "cpu-sustained",
                    level: snapshot.cpuUsagePercent >= configuration.cpuHighUsageThreshold + 15 ? .high : .moderate,
                    title: "CPU Load High",
                    message: "CPU usage is above the configured threshold.",
                    symbolName: "cpu"
                )
            )
        }

        let memoryRatio = snapshot.memoryTotalBytes > 0 ? Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes) : 0
        if memoryRatio >= configuration.memoryHighWatermark || snapshot.memoryPressure == .high {
            alerts.append(
                FluxAlert(
                    id: "memory-pressure",
                    level: snapshot.memoryPressure == .high ? .high : .moderate,
                    title: "Memory Pressure",
                    message: "RAM usage is elevated and may be adding compression or swap work.",
                    symbolName: "memorychip"
                )
            )
        }

        if snapshot.downloadBytesPerSecond + snapshot.uploadBytesPerSecond >= configuration.networkHighWatermarkBytesPerSecond {
            alerts.append(
                FluxAlert(
                    id: "network-throughput",
                    level: .moderate,
                    title: "Network Throughput High",
                    message: "Sustained transfer activity is contributing background load.",
                    symbolName: "arrow.up.arrow.down"
                )
            )
        }

        if let cpuTemp = snapshot.temperature.cpuCelsius, cpuTemp >= 85 {
            alerts.append(
                FluxAlert(
                    id: "cpu-temp-high",
                    level: cpuTemp >= 92 ? .critical : .high,
                    title: "CPU Temperature High",
                    message: "CPU temperature is already elevated at \(MetricsFormatter.temperatureWithUnit(cpuTemp)).",
                    symbolName: "thermometer.high"
                )
            )
        }

        return alerts
    }

    private func maybeSendNotification(for alert: FluxAlert, cooldown: TimeInterval) {
        let now = Date()
        if let previous = lastNotificationAt[alert.id], now.timeIntervalSince(previous) < cooldown {
            return
        }

        lastNotificationAt[alert.id] = now

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fluxbar.\(alert.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

private struct CommandRunner {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    static func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandRunner {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return CommandRunner(standardOutput: "", standardError: error.localizedDescription, exitCode: 1)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        if process.isRunning {
            process.terminate()
            return CommandRunner(standardOutput: "", standardError: "Command timed out", exitCode: 124)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandRunner(
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}
