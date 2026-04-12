import Foundation

enum NotificationSupport {
    static var isAvailableInCurrentRunMode: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
