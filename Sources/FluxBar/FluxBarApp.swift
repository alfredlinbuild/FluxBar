import SwiftUI

@main
struct FluxBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: FluxBarSettings
    @StateObject private var monitor: SystemMonitor

    init() {
        let settings = FluxBarSettings()
        let monitor = SystemMonitor(settings: settings)
        monitor.startIfNeeded()
        FluxBarRuntime.settings = settings
        FluxBarRuntime.monitor = monitor
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: monitor)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(monitor)
                .frame(width: 520, height: 500)
        }
    }
}
