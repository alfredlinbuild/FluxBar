import Foundation
import ServiceManagement
import UserNotifications

struct MonitoringConfiguration: Sendable {
    let refreshInterval: TimeInterval
    let cpuHighUsageThreshold: Double
    let memoryHighWatermark: Double
    let networkHighWatermarkBytesPerSecond: Double
    let preferredSingleMetric: SingleMetricKind
    let topProcessSortMode: TopProcessSortMode
    let showTemperature: Bool
    let showNetwork: Bool
    let showMemory: Bool
    let showCPUUsage: Bool
    let heatAnalysisEnabled: Bool
    let alertsEnabled: Bool
    let notificationCooldown: TimeInterval
    let notificationsEnabled: Bool
}

@MainActor
final class FluxBarSettings: ObservableObject {
    @Published var menuBarMode: MenuBarModePreference {
        didSet { save(menuBarMode.rawValue, forKey: Keys.menuBarMode) }
    }

    @Published var preferredSingleMetric: SingleMetricKind {
        didSet { save(preferredSingleMetric.rawValue, forKey: Keys.singleMetric) }
    }

    @Published var menuBarModules: [MenuBarModule] {
        didSet { save(menuBarModules.map(\.rawValue), forKey: Keys.menuBarModules) }
    }

    @Published var topProcessSortMode: TopProcessSortMode {
        didSet { save(topProcessSortMode.rawValue, forKey: Keys.topProcessSortMode) }
    }

    @Published var refreshInterval: Double {
        didSet { save(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var showTemperature: Bool {
        didSet { save(showTemperature, forKey: Keys.showTemperature) }
    }

    @Published var showNetwork: Bool {
        didSet { save(showNetwork, forKey: Keys.showNetwork) }
    }

    @Published var showMemory: Bool {
        didSet { save(showMemory, forKey: Keys.showMemory) }
    }

    @Published var showCPUUsage: Bool {
        didSet { save(showCPUUsage, forKey: Keys.showCPUUsage) }
    }

    @Published var showStatusSection: Bool {
        didSet { save(showStatusSection, forKey: Keys.showStatusSection) }
    }

    @Published var showTopProcessesSection: Bool {
        didSet { save(showTopProcessesSection, forKey: Keys.showTopProcessesSection) }
    }

    @Published var overviewFlexibleSlotMode: OverviewFlexibleSlotMode {
        didSet { save(overviewFlexibleSlotMode.rawValue, forKey: Keys.overviewFlexibleSlotMode) }
    }

    @Published var heatAnalysisEnabled: Bool {
        didSet { save(heatAnalysisEnabled, forKey: Keys.heatAnalysisEnabled) }
    }

    @Published var cpuHighUsageThreshold: Double {
        didSet { save(cpuHighUsageThreshold, forKey: Keys.cpuHighUsageThreshold) }
    }

    @Published var memoryHighWatermark: Double {
        didSet { save(memoryHighWatermark, forKey: Keys.memoryHighWatermark) }
    }

    @Published var networkHighWatermarkMBps: Double {
        didSet { save(networkHighWatermarkMBps, forKey: Keys.networkHighWatermarkMBps) }
    }

    @Published var alertsEnabled: Bool {
        didSet { save(alertsEnabled, forKey: Keys.alertsEnabled) }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            save(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled {
                Task { await requestNotificationAuthorization() }
            }
        }
    }

    @Published var notificationCooldownMinutes: Double {
        didSet { save(notificationCooldownMinutes, forKey: Keys.notificationCooldownMinutes) }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet {
            save(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled)
            Task { await updateLaunchAtLogin() }
        }
    }

    @Published private(set) var launchAtLoginMessage: String = "Launch at login is only available when FluxBar runs as a bundled app."
    @Published private(set) var notificationsStatusMessage: String = "Notifications are optional and use cooldown throttling."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMode = MenuBarModePreference(rawValue: defaults.string(forKey: Keys.menuBarMode) ?? "") ?? .automatic
        menuBarMode = storedMode == .singleMetric ? .automatic : storedMode
        preferredSingleMetric = SingleMetricKind(rawValue: defaults.string(forKey: Keys.singleMetric) ?? "") ?? .temperature
        topProcessSortMode = TopProcessSortMode(rawValue: defaults.string(forKey: Keys.topProcessSortMode) ?? "") ?? .heatingImpact
        refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? Double ?? 2.0
        showTemperature = true
        showNetwork = defaults.object(forKey: Keys.showNetwork) as? Bool ?? true
        showMemory = defaults.object(forKey: Keys.showMemory) as? Bool ?? true
        showCPUUsage = defaults.object(forKey: Keys.showCPUUsage) as? Bool ?? true
        let storedModules = defaults.stringArray(forKey: Keys.menuBarModules)
        let normalizedModules = Self.normalizedMenuBarModules(storedModules)
        menuBarModules = normalizedModules
        showStatusSection = defaults.object(forKey: Keys.showStatusSection) as? Bool ?? false
        showTopProcessesSection = defaults.object(forKey: Keys.showTopProcessesSection) as? Bool ?? false
        overviewFlexibleSlotMode = OverviewFlexibleSlotMode(rawValue: defaults.string(forKey: Keys.overviewFlexibleSlotMode) ?? "") ?? .thermal
        heatAnalysisEnabled = defaults.object(forKey: Keys.heatAnalysisEnabled) as? Bool ?? true
        cpuHighUsageThreshold = defaults.object(forKey: Keys.cpuHighUsageThreshold) as? Double ?? 68
        memoryHighWatermark = defaults.object(forKey: Keys.memoryHighWatermark) as? Double ?? 0.78
        networkHighWatermarkMBps = defaults.object(forKey: Keys.networkHighWatermarkMBps) as? Double ?? 6
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? false
        notificationCooldownMinutes = defaults.object(forKey: Keys.notificationCooldownMinutes) as? Double ?? 10
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? false

        if storedModules != normalizedModules.map(\.rawValue) {
            save(normalizedModules.map(\.rawValue), forKey: Keys.menuBarModules)
        }

        Task { await syncLaunchAtLoginStatus() }
        Task { await syncNotificationStatus() }
        save(true, forKey: Keys.showTemperature)
    }

    var monitoringConfiguration: MonitoringConfiguration {
        MonitoringConfiguration(
            refreshInterval: refreshInterval,
            cpuHighUsageThreshold: cpuHighUsageThreshold,
            memoryHighWatermark: memoryHighWatermark,
            networkHighWatermarkBytesPerSecond: networkHighWatermarkMBps * 1_048_576,
            preferredSingleMetric: preferredSingleMetric,
            topProcessSortMode: topProcessSortMode,
            showTemperature: true,
            showNetwork: showNetwork,
            showMemory: showMemory,
            showCPUUsage: showCPUUsage,
            heatAnalysisEnabled: heatAnalysisEnabled,
            alertsEnabled: alertsEnabled,
            notificationCooldown: notificationCooldownMinutes * 60,
            notificationsEnabled: notificationsEnabled
        )
    }

    func resetToStableDefaults() {
        menuBarMode = .automatic
        preferredSingleMetric = .temperature
        menuBarModules = Self.defaultMenuBarModules
        topProcessSortMode = .heatingImpact
        refreshInterval = 2.0
        showTemperature = true
        showNetwork = true
        showMemory = true
        showCPUUsage = true
        showStatusSection = false
        showTopProcessesSection = false
        overviewFlexibleSlotMode = .thermal
        heatAnalysisEnabled = true
        cpuHighUsageThreshold = 68
        memoryHighWatermark = 0.78
        networkHighWatermarkMBps = 6
        alertsEnabled = true
        notificationsEnabled = false
        notificationCooldownMinutes = 10
    }

    private func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func isMenuBarModuleVisible(_ module: MenuBarModule) -> Bool {
        switch module {
        case .temperature:
            return true
        case .network:
            return showNetwork
        case .memory:
            return showMemory
        case .cpu:
            return showCPUUsage
        }
    }

    func setMenuBarModuleVisibility(_ module: MenuBarModule, isVisible: Bool) {
        switch module {
        case .temperature:
            showTemperature = true
        case .network:
            showNetwork = isVisible
        case .memory:
            showMemory = isVisible
        case .cpu:
            showCPUUsage = isVisible
        }
    }

    func moveMenuBarModuleUp(_ module: MenuBarModule) {
        guard let index = menuBarModules.firstIndex(of: module), index > 0 else { return }
        menuBarModules.swapAt(index, index - 1)
    }

    func moveMenuBarModuleDown(_ module: MenuBarModule) {
        guard let index = menuBarModules.firstIndex(of: module), index < menuBarModules.count - 1 else { return }
        menuBarModules.swapAt(index, index + 1)
    }

    func canMoveMenuBarModuleUp(_ module: MenuBarModule) -> Bool {
        guard let index = menuBarModules.firstIndex(of: module) else { return false }
        return index > 0
    }

    func canMoveMenuBarModuleDown(_ module: MenuBarModule) -> Bool {
        guard let index = menuBarModules.firstIndex(of: module) else { return false }
        return index < menuBarModules.count - 1
    }

    var movableMenuBarModules: [MenuBarModule] {
        menuBarModules.filter { $0 != .temperature }
    }

    func moveMovableMenuBarModules(from source: IndexSet, to destination: Int) {
        var reordered = movableMenuBarModules
        reordered.move(fromOffsets: source, toOffset: destination)
        menuBarModules = [.temperature] + reordered
    }

    private func syncLaunchAtLoginStatus() async {
        guard #available(macOS 13.0, *) else {
            launchAtLoginMessage = "Launch at login requires macOS 13 or later."
            return
        }

        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            launchAtLoginMessage = "FluxBar will open at login."
        case .notRegistered:
            launchAtLoginMessage = "Bundle the app to enable launch at login."
        case .requiresApproval:
            launchAtLoginMessage = "macOS requires approval in Login Items."
        case .notFound:
            launchAtLoginMessage = "SMAppService could not find a bundled app target."
        @unknown default:
            launchAtLoginMessage = "Launch at login status is unavailable."
        }
    }

    private func updateLaunchAtLogin() async {
        guard #available(macOS 13.0, *) else {
            launchAtLoginEnabled = false
            launchAtLoginMessage = "Launch at login requires macOS 13 or later."
            return
        }

        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            await syncLaunchAtLoginStatus()
        } catch {
            launchAtLoginEnabled = false
            launchAtLoginMessage = "Launch at login needs a signed bundled app."
        }
    }

    private func requestNotificationAuthorization() async {
        guard NotificationSupport.isAvailableInCurrentRunMode else {
            notificationsEnabled = false
            notificationsStatusMessage = "Notifications require launching FluxBar as a bundled .app."
            return
        }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationsStatusMessage = granted ? "Notifications authorized." : "Notifications were not authorized."
        } catch {
            notificationsEnabled = false
            notificationsStatusMessage = "Notification authorization failed."
        }
    }

    private func syncNotificationStatus() async {
        guard NotificationSupport.isAvailableInCurrentRunMode else {
            notificationsStatusMessage = "Notifications require launching FluxBar as a bundled .app."
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsStatusMessage = "Notifications authorized."
        case .denied:
            notificationsStatusMessage = "Notifications denied in System Settings."
        case .notDetermined:
            notificationsStatusMessage = "Notifications are optional and use cooldown throttling."
        @unknown default:
            notificationsStatusMessage = "Notification status unavailable."
        }
    }

    private enum Keys {
        static let menuBarMode = "menuBarMode"
        static let singleMetric = "singleMetric"
        static let menuBarModules = "menuBarModules"
        static let topProcessSortMode = "topProcessSortMode"
        static let refreshInterval = "refreshInterval"
        static let showTemperature = "showTemperature"
        static let showNetwork = "showNetwork"
        static let showMemory = "showMemory"
        static let showCPUUsage = "showCPUUsage"
        static let showStatusSection = "showStatusSection"
        static let showTopProcessesSection = "showTopProcessesSection"
        static let overviewFlexibleSlotMode = "overviewFlexibleSlotMode"
        static let heatAnalysisEnabled = "heatAnalysisEnabled"
        static let cpuHighUsageThreshold = "cpuHighUsageThreshold"
        static let memoryHighWatermark = "memoryHighWatermark"
        static let networkHighWatermarkMBps = "networkHighWatermarkMBps"
        static let alertsEnabled = "alertsEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationCooldownMinutes = "notificationCooldownMinutes"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    private static let defaultMenuBarModules: [MenuBarModule] = [.temperature, .cpu, .memory, .network]

    private static func normalizedMenuBarModules(_ stored: [String]?) -> [MenuBarModule] {
        let decoded = (stored ?? []).compactMap(MenuBarModule.init(rawValue:))
        let unique = decoded.reduce(into: [MenuBarModule]()) { result, module in
            if !result.contains(module) {
                result.append(module)
            }
        }
        if unique.isEmpty {
            return defaultMenuBarModules
        }

        var normalized = unique
        if let temperatureIndex = normalized.firstIndex(of: .temperature) {
            normalized.remove(at: temperatureIndex)
        }
        normalized.insert(.temperature, at: 0)

        for module in defaultMenuBarModules where !normalized.contains(module) {
            normalized.append(module)
        }
        return normalized
    }
}
