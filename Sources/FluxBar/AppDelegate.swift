import AppKit
import Combine
import SwiftUI

@MainActor
enum FluxBarRuntime {
    static var settings: FluxBarSettings?
    static var monitor: SystemMonitor?

    static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let settingsWindow = NSApp.windows.first(where: { $0.title.localizedCaseInsensitiveContains("settings") }) {
                settingsWindow.makeKeyAndOrderFront(nil)
            } else if let frontWindow = NSApp.windows.first(where: { !$0.title.isEmpty }) {
                frontWindow.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "debug_appDidFinishLaunching_at")
        NSApp.setActivationPolicy(.regular)
        installStatusBarIfPossible()
        DispatchQueue.main.async { [weak self] in
            self?.installStatusBarIfPossible()
        }
    }

    private func installStatusBarIfPossible() {
        guard statusBarController == nil,
              let settings = FluxBarRuntime.settings,
              let monitor = FluxBarRuntime.monitor else {
            debugStatusLog("installStatusBarIfPossible skipped controller=\(statusBarController != nil) settings=\(FluxBarRuntime.settings != nil) monitor=\(FluxBarRuntime.monitor != nil)")
            return
        }

        debugStatusLog("installStatusBarIfPossible creating controller")
        statusBarController = StatusBarController(settings: settings, monitor: monitor)
    }
}

@MainActor
private final class StatusBarController {
    private let settings: FluxBarSettings
    private let monitor: SystemMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let statusView = StatusBarContentView(frame: .zero)
    private var cancellables: Set<AnyCancellable> = []
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    init(settings: FluxBarSettings, monitor: SystemMonitor) {
        self.settings = settings
        self.monitor = monitor

        configurePopover()
        configureStatusItem()
        bindState()
        refreshStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 380, height: 640)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanelView()
                .environmentObject(settings)
                .environmentObject(monitor)
                .frame(width: 380, height: 640)
        )
    }

    private func configureStatusItem(retryCount: Int = 0) {
        guard let button = statusItem.button else {
            UserDefaults.standard.set(retryCount, forKey: "debug_statusItem_button_nil_retry")
            debugStatusLog("configureStatusItem button=nil retry=\(retryCount)")
            guard retryCount < 20 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.configureStatusItem(retryCount: retryCount + 1)
            }
            return
        }

        if statusView.superview === button {
            UserDefaults.standard.set(true, forKey: "debug_statusItem_already_attached")
            debugStatusLog("configureStatusItem already attached")
            return
        }

        UserDefaults.standard.set(true, forKey: "debug_statusItem_attach_success")
        debugStatusLog("configureStatusItem attaching custom status view")

        button.title = ""
        button.image = nil
        button.isBordered = false
        button.target = self
        button.action = #selector(handleStatusItemButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.addSubview(statusView)
        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.onClick = { [weak self] in
            self?.togglePopover()
        }

        NSLayoutConstraint.activate([
            statusView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusView.topAnchor.constraint(equalTo: button.topAnchor),
            statusView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }

    @objc private func handleStatusItemButtonClick(_ sender: NSStatusBarButton) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "debug_statusItem_buttonAction_at")
        togglePopover()
    }

    private func bindState() {
        monitor.$latestSnapshot
            .combineLatest(monitor.$latestAssessment)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            settings.$menuBarMode.map { _ in () }.eraseToAnyPublisher(),
            settings.$preferredSingleMetric.map { _ in () }.eraseToAnyPublisher(),
            settings.$menuBarModules.map { _ in () }.eraseToAnyPublisher(),
            settings.$showTemperature.map { _ in () }.eraseToAnyPublisher(),
            settings.$showNetwork.map { _ in () }.eraseToAnyPublisher(),
            settings.$showMemory.map { _ in () }.eraseToAnyPublisher(),
            settings.$showCPUUsage.map { _ in () }.eraseToAnyPublisher()
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "debug_popover_toggle_at")
        UserDefaults.standard.set(popover.isShown, forKey: "debug_popover_wasShown_beforeToggle")

        if popover.isShown {
            closePopover()
            UserDefaults.standard.set(false, forKey: "debug_popover_isShown_afterToggle")
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let popoverWindow = popover.contentViewController?.view.window {
                popoverWindow.collectionBehavior.insert([.fullScreenAuxiliary, .moveToActiveSpace, .transient])
                popoverWindow.level = .statusBar
                popoverWindow.becomeKey()
                UserDefaults.standard.set(NSStringFromRect(popoverWindow.frame), forKey: "debug_popover_windowFrame")
                UserDefaults.standard.set(NSNumber(value: Int(popoverWindow.level.rawValue)), forKey: "debug_popover_windowLevel")
            }
            UserDefaults.standard.set(popover.isShown, forKey: "debug_popover_isShown_afterToggle")
            installPopoverObservers()
        }
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        removePopoverObservers()
    }

    private func installPopoverObservers() {
        removePopoverObservers()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.eventHitsFluxBar(event) {
                return event
            }
            self.closePopover()
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removePopoverObservers() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }

    private func eventHitsFluxBar(_ event: NSEvent) -> Bool {
        let location = NSEvent.mouseLocation

        if let button = statusItem.button {
            let buttonFrame = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero
            if buttonFrame.contains(location) {
                return true
            }
        }

        if let window = popover.contentViewController?.view.window {
            return window.frame.contains(location)
        }

        return false
    }

    private func refreshStatusItem() {
        let model = StatusItemRenderModel(
            snapshot: monitor.latestSnapshot,
            assessment: monitor.latestAssessment,
            settings: settings
        )

        statusView.render(model: model)
        statusItem.length = model.width
        UserDefaults.standard.set(model.width, forKey: "debug_statusItem_width")
        UserDefaults.standard.set(statusView.superview != nil, forKey: "debug_statusItem_hasSuperview")
        if let button = statusItem.button, let window = button.window {
            let screenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            UserDefaults.standard.set(NSStringFromRect(screenFrame), forKey: "debug_statusItem_screenFrame")
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "debug_statusItem_windowFrame")
        } else {
            UserDefaults.standard.set("nil", forKey: "debug_statusItem_screenFrame")
        }
        debugStatusLog("refreshStatusItem width=\(model.width) mode=\(model.presentation.mode.rawValue) hasSuperview=\(statusView.superview != nil)")
    }
}

@MainActor
private func debugStatusLog(_ message: String) {
    let path = "/tmp/fluxbar-status-debug.log"
    let line = "[\(Date())] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        }
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
struct StatusItemRenderModel {
    let presentation: MenuBarPresentation
    let temperatureText: String
    let cpuRatio: Double?
    let memoryRatio: Double?
    let uploadText: String?
    let downloadText: String?
    let showsDashboard: Bool
    let dashboardModules: [MenuBarModule]
    let width: CGFloat

    init(snapshot: SystemSnapshot?, assessment: HeatAssessment, settings: FluxBarSettings) {
        presentation = MenuBarPresentationEngine.makePresentation(
            snapshot: snapshot,
            assessment: assessment,
            settings: settings
        )

        showsDashboard = presentation.mode == .standard || presentation.mode == .compact
        dashboardModules = showsDashboard
            ? settings.menuBarModules.filter { module in
                switch module {
                case .temperature:
                    return true
                case .network:
                    return settings.showNetwork
                case .memory:
                    return settings.showMemory
                case .cpu:
                    return settings.showCPUUsage
                }
            }
            : []

        if let snapshot {
            temperatureText = MetricsFormatter.temperature(
                snapshot.temperature.cpuCelsius ?? snapshot.temperature.gpuCelsius
            )
            cpuRatio = settings.showCPUUsage ? min(max(snapshot.cpuUsagePercent / 100, 0), 1) : nil
            if snapshot.memoryTotalBytes > 0, settings.showMemory {
                memoryRatio = min(
                    max(Double(snapshot.memoryUsedBytes) / Double(snapshot.memoryTotalBytes), 0),
                    1
                )
            } else {
                memoryRatio = nil
            }
            uploadText = settings.showNetwork ? MetricsFormatter.menuBarStackedThroughput(snapshot.uploadBytesPerSecond) : nil
            downloadText = settings.showNetwork ? MetricsFormatter.menuBarStackedThroughput(snapshot.downloadBytesPerSecond) : nil
        } else {
            temperatureText = MetricsFormatter.temperature(nil)
            cpuRatio = nil
            memoryRatio = nil
            uploadText = nil
            downloadText = nil
        }

        if showsDashboard {
            width = Self.dashboardWidth(modules: dashboardModules)
        } else {
            width = presentation.fixedWidth
        }
    }

    private static func dashboardWidth(modules: [MenuBarModule]) -> CGFloat {
        let meterGroupWidth: CGFloat = 25
        let meterSpacing: CGFloat = 8
        let networkTrailingSpacing: CGFloat = 5
        let thermometerWidth: CGFloat = 14
        let thermometerGap: CGFloat = 4
        let temperatureWidth: CGFloat = 21
        let clusterGap: CGFloat = 5
        let leadingInset: CGFloat = 4
        let trailingInset: CGFloat = 4

        let trailingModules = modules.filter { $0 != .temperature }
        let trailingContentWidth = trailingModules.enumerated().reduce(CGFloat.zero) { partial, item in
            let (index, module) = item
            let moduleWidth: CGFloat = module == .network ? 58 : meterGroupWidth
            let spacingBefore: CGFloat
            if index == 0 {
                spacingBefore = 0
            } else {
                let previousModule = trailingModules[index - 1]
                spacingBefore = previousModule == .network ? networkTrailingSpacing : meterSpacing
            }
            return partial + moduleWidth + spacingBefore
        }

        return leadingInset
            + thermometerWidth
            + thermometerGap
            + temperatureWidth
            + (trailingContentWidth > 0 ? clusterGap : 0)
            + trailingContentWidth
            + trailingInset
    }
}

@MainActor
final class StatusBarContentView: NSView {
    var onClick: (() -> Void)?

    private var model: StatusItemRenderModel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: model?.width ?? 96, height: NSStatusBar.system.thickness)
    }

    func render(model: StatusItemRenderModel) {
        self.model = model
        toolTip = model.presentation.helpText
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }

        if model.showsDashboard {
            drawDashboard(model: model, in: bounds)
        } else if model.presentation.mode == .icon {
            drawIconLine(model: model, in: bounds)
        } else if model.presentation.mode == .singleMetric,
                  model.presentation.symbolName == "thermometer.medium" {
            drawTemperatureSingleMetric(model: model, in: bounds)
        } else {
            drawSingleLine(model: model, in: bounds)
        }
    }

    private func drawSingleLine(model: StatusItemRenderModel, in bounds: NSRect) {
        drawThermometerSymbol(named: model.presentation.symbolName, in: NSRect(x: 4, y: 1, width: 10, height: 16))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: 22, y: 4, width: max(bounds.width - 24, 24), height: 12)
        (model.presentation.label ?? "").draw(in: textRect, withAttributes: attributes)
    }

    private func drawTemperatureSingleMetric(model: StatusItemRenderModel, in bounds: NSRect) {
        let contentRect = bounds.insetBy(dx: 4, dy: 2)
        let moduleY = contentRect.minY + 1
        let thermometerRect = NSRect(x: contentRect.minX, y: moduleY - 4, width: 15, height: 25)
        drawThermometerSymbol(named: model.presentation.symbolName, in: thermometerRect)

        let label = model.presentation.label ?? model.temperatureText
        drawTemperatureValue(
            label,
            in: NSRect(
                x: thermometerRect.maxX + 4,
                y: moduleY + 0.8,
                width: max(bounds.width - thermometerRect.maxX - 8, 24),
                height: 16
            )
        )
    }

    private func drawIconLine(model: StatusItemRenderModel, in bounds: NSRect) {
        let contentRect = bounds.insetBy(dx: 4, dy: 2)
        let symbolRect = NSRect(x: contentRect.minX, y: contentRect.minY + 1, width: 16, height: 16)
        drawStatusSymbol(named: model.presentation.symbolName, in: symbolRect, pointSize: 14, weight: .semibold)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: model.presentation.label ?? "", attributes: attributes)
        let size = attributed.size()
        let textRect = NSRect(
            x: symbolRect.maxX + 5,
            y: contentRect.midY - (size.height / 2) - 0.2,
            width: max(bounds.width - symbolRect.maxX - 9, 24),
            height: size.height
        )
        attributed.draw(in: textRect)
    }

    private func drawDashboard(model: StatusItemRenderModel, in bounds: NSRect) {
        let contentRect = bounds.insetBy(dx: 4, dy: 2)
        let moduleY = contentRect.minY + 1
        let moduleHeight: CGFloat = 16
        let temperatureModuleWidth: CGFloat = 15 + 4 + 21
        let moduleSpacing: CGFloat = 8
        let temperatureTrailingSpacing: CGFloat = 5
        let networkTrailingSpacing: CGFloat = 5
        var x = contentRect.minX

        for module in model.dashboardModules {
            switch module {
            case .temperature:
                let thermometerRect = NSRect(x: x, y: moduleY - 4, width: 15, height: 25)
                drawThermometerSymbol(named: model.presentation.symbolName, in: thermometerRect)
                drawTemperatureValue(
                    model.temperatureText,
                    in: NSRect(x: thermometerRect.maxX + 4, y: moduleY + 0.8, width: 21, height: moduleHeight)
                )
                x += temperatureModuleWidth
            case .cpu:
                drawMeterGroup(
                    MeterDrawSpec(label: "CPU", ratio: model.cpuRatio, tint: .systemOrange),
                    atX: x,
                    y: moduleY - 3,
                    height: moduleHeight
                )
                x += 25
            case .memory:
                drawMeterGroup(
                    MeterDrawSpec(label: "MEM", ratio: model.memoryRatio, tint: .systemBlue),
                    atX: x,
                    y: moduleY - 3,
                    height: moduleHeight
                )
                x += 25
            case .network:
                drawNetworkBlock(
                    uploadText: model.uploadText ?? "0KB/s",
                    downloadText: model.downloadText ?? "0KB/s",
                    atX: x,
                    y: moduleY - 3,
                    height: moduleHeight
                )
                x += 58
            }

            if module != model.dashboardModules.last {
                if module == .temperature {
                    x += temperatureTrailingSpacing
                } else if module == .network {
                    x += networkTrailingSpacing
                } else {
                    x += moduleSpacing
                }
            }
        }
    }

    private func drawTemperatureValue(_ value: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: value, attributes: attributes)
        let size = attributed.size()
        let point = CGPoint(
            x: rect.minX,
            y: rect.midY - (size.height / 2) - 0.35
        )
        attributed.draw(at: point)
    }

    private func drawMeterGroup(_ spec: MeterDrawSpec, atX x: CGFloat, y: CGFloat, height: CGFloat) {
        let labelRect = NSRect(x: x, y: y, width: 13, height: height)
        let layout = verticalLabelLayout(in: labelRect)

        drawVerticalLabel(spec.label, in: labelRect, layout: layout)
        drawMeter(
            ratio: spec.ratio,
            tint: spec.tint,
            in: NSRect(
                x: x + 15,
                y: layout.originY,
                width: 10,
                height: layout.visibleHeight
            )
        )
    }

    private func drawVerticalLabel(_ text: String, in rect: NSRect, layout: VerticalLabelLayout) {
        let letters = text.map { String($0) }

        for (index, letter) in letters.enumerated() {
            let attributed = NSAttributedString(string: letter, attributes: layout.attributes)
            let size = attributed.size()
            let point = CGPoint(
                x: rect.midX - (size.width / 2),
                y: layout.originY + (CGFloat(index) * layout.lineHeight) - 0.4
            )
            attributed.draw(at: point)
        }
    }

    private func verticalLabelLayout(in rect: NSRect) -> VerticalLabelLayout {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.2, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let lineHeight: CGFloat = 6.55
        let glyphHeight = NSAttributedString(string: "M", attributes: attributes).size().height
        let visibleHeight = glyphHeight + (lineHeight * 2)
        let originY = rect.minY + max((rect.height - visibleHeight) / 2, 0)

        return VerticalLabelLayout(
            attributes: attributes,
            lineHeight: lineHeight,
            glyphHeight: glyphHeight,
            originY: originY
        )
    }

    private func drawMeter(ratio: Double?, tint: NSColor, in rect: NSRect) {
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        capsule.fill()

        if let ratio {
            let clamped = min(max(ratio, 0), 1)
            let fillHeight = 3 + ((rect.height - 5) * clamped)
            let fillRect = NSRect(
                x: rect.minX + 1,
                y: rect.maxY - fillHeight - 1,
                width: rect.width - 2,
                height: fillHeight
            )
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: fillRect.width / 2, yRadius: fillRect.width / 2)
            tint.setFill()
            fillPath.fill()
        } else {
            let dashed = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
            dashed.lineWidth = 1
            dashed.setLineDash([2, 2], count: 2, phase: 0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
            dashed.stroke()
        }
    }

    private func drawNetworkBlock(uploadText: String, downloadText: String, atX x: CGFloat, y: CGFloat, height: CGFloat) {
        let blockTop = y - 0.6
        drawNetworkLine(symbol: "↑", value: uploadText, at: CGPoint(x: x, y: blockTop))
        drawNetworkLine(symbol: "↓", value: downloadText, at: CGPoint(x: x, y: blockTop + 9.4))
    }

    private func drawNetworkLine(symbol: String, value: String, at origin: CGPoint) {
        let symbolAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]

        let valueParagraph = NSMutableParagraphStyle()
        valueParagraph.alignment = .right
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: valueParagraph
        ]

        let unitParagraph = NSMutableParagraphStyle()
        unitParagraph.alignment = .right
        let unitAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.2, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: unitParagraph
        ]

        let symbolText = NSAttributedString(string: symbol, attributes: symbolAttributes)
        let (numberPart, unitPart) = splitNetworkThroughput(value)
        let valueText = NSAttributedString(string: numberPart, attributes: valueAttributes)
        let unitText = NSAttributedString(string: unitPart, attributes: unitAttributes)
        let symbolSize = symbolText.size()
        let valueSize = valueText.size()
        let unitSize = unitText.size()

        let numberColumnX = origin.x + 12
        let numberColumnWidth: CGFloat = 18
        let unitColumnX = numberColumnX + numberColumnWidth
        let unitColumnWidth: CGFloat = 20
        let textY = origin.y + max((symbolSize.height - valueSize.height) / 2, 0) - 0.2
        let unitY = origin.y + max((symbolSize.height - unitSize.height) / 2, 0) + 0.3

        symbolText.draw(at: CGPoint(x: origin.x, y: origin.y))
        valueText.draw(
            in: NSRect(x: numberColumnX, y: textY, width: numberColumnWidth, height: valueSize.height + 1)
        )
        unitText.draw(
            in: NSRect(x: unitColumnX, y: unitY, width: unitColumnWidth, height: unitSize.height + 1)
        )
    }

    private func splitNetworkThroughput(_ value: String) -> (number: String, unit: String) {
        guard !value.isEmpty else { return ("0", "KB/s") }
        guard let unitStart = value.firstIndex(where: { $0.isLetter }) else {
            return (value, "KB/s")
        }
        let number = String(value[..<unitStart])
        let unit = String(value[unitStart...])
        return (number.isEmpty ? "0" : number, unit.isEmpty ? "KB/s" : unit)
    }

    private func drawThermometerSymbol(named symbolName: String, in rect: NSRect) {
        drawStatusSymbol(named: symbolName, in: rect, pointSize: 18, weight: .semibold)
    }

    private func drawStatusSymbol(
        named symbolName: String,
        in rect: NSRect,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) {
        let baseConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let tintedConfiguration = baseConfiguration.applying(
            NSImage.SymbolConfiguration(hierarchicalColor: .labelColor)
        )
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(tintedConfiguration) else {
            return
        }

        let imageSize = image.size
        let widthScale = rect.width / max(imageSize.width, 1)
        let heightScale = rect.height / max(imageSize.height, 1)
        let scale = min(widthScale, heightScale)
        let targetSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = NSRect(
            x: rect.midX - (targetSize.width / 2),
            y: rect.midY - (targetSize.height / 2) + 0.2,
            width: targetSize.width,
            height: targetSize.height
        )

        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

final class StatusBarPreviewContainerView: NSView {
    private let contentView = StatusBarContentView(frame: .zero)
    private var cancellables: Set<AnyCancellable> = []
    private weak var settings: FluxBarSettings?
    private weak var monitor: SystemMonitor?
    private var model: StatusItemRenderModel?
    private let railInsets = NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(contentView)
        contentView.setContentHuggingPriority(.required, for: .horizontal)
        contentView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 420, height: 102)
    }

    override func layout() {
        super.layout()
        updateContentFrame()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }

        let railRect = bounds.insetBy(dx: 8, dy: 6)
        let railPath = NSBezierPath(roundedRect: railRect, xRadius: 18, yRadius: 18)
        NSColor.controlBackgroundColor.setFill()
        railPath.fill()
        NSColor.labelColor.withAlphaComponent(0.04).setStroke()
        railPath.lineWidth = 1
        railPath.stroke()

        drawRailGuides(in: railRect)
        drawDebugFootprints(for: model, around: contentView.frame)
    }

    func configure(settings: FluxBarSettings, monitor: SystemMonitor) {
        if self.settings === settings, self.monitor === monitor {
            refresh()
            return
        }

        self.settings = settings
        self.monitor = monitor
        cancellables.removeAll()

        monitor.$latestSnapshot
            .combineLatest(monitor.$latestAssessment)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            settings.$menuBarMode.map { _ in () }.eraseToAnyPublisher(),
            settings.$preferredSingleMetric.map { _ in () }.eraseToAnyPublisher(),
            settings.$menuBarModules.map { _ in () }.eraseToAnyPublisher(),
            settings.$showTemperature.map { _ in () }.eraseToAnyPublisher(),
            settings.$showNetwork.map { _ in () }.eraseToAnyPublisher(),
            settings.$showMemory.map { _ in () }.eraseToAnyPublisher(),
            settings.$showCPUUsage.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refresh()
        }
        .store(in: &cancellables)

        refresh()
    }

    private func refresh() {
        guard let settings, let monitor else { return }

        let model = StatusItemRenderModel(
            snapshot: monitor.latestSnapshot,
            assessment: monitor.latestAssessment,
            settings: settings
        )
        self.model = model
        contentView.render(model: model)
        updateContentFrame()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func updateContentFrame() {
        guard let model else { return }

        let previewSize = NSSize(width: model.width, height: NSStatusBar.system.thickness)
        let previewOriginX = bounds.midX - (previewSize.width / 2)
        let previewOriginY = bounds.midY - (previewSize.height / 2)
        contentView.frame = NSRect(origin: CGPoint(x: previewOriginX, y: previewOriginY), size: previewSize)
    }

    private func drawRailGuides(in railRect: NSRect) {
        let topY = railRect.minY + railInsets.top
        let bottomY = railRect.maxY - railInsets.bottom
        let leftX = railRect.minX + railInsets.left
        let rightX = railRect.maxX - railInsets.right
        let centerY = railRect.midY

        drawDashedLine(from: CGPoint(x: leftX, y: topY), to: CGPoint(x: rightX, y: topY), color: .labelColor.withAlphaComponent(0.10))
        drawDashedLine(from: CGPoint(x: leftX, y: bottomY), to: CGPoint(x: rightX, y: bottomY), color: .labelColor.withAlphaComponent(0.10))
        drawDashedLine(from: CGPoint(x: leftX, y: topY), to: CGPoint(x: leftX, y: bottomY), color: .labelColor.withAlphaComponent(0.10))
        drawDashedLine(from: CGPoint(x: rightX, y: topY), to: CGPoint(x: rightX, y: bottomY), color: .labelColor.withAlphaComponent(0.10))
        drawDashedLine(from: CGPoint(x: leftX, y: centerY), to: CGPoint(x: rightX, y: centerY), color: NSColor.systemBlue.withAlphaComponent(0.14))
    }

    private func drawDebugFootprints(for model: StatusItemRenderModel, around previewFrame: NSRect) {
        drawFootprintBoxes(debugFootprints(for: model, in: previewFrame))
    }

    private func drawFootprintBoxes(_ footprints: [DebugPreviewFootprint]) {
        guard !footprints.isEmpty else { return }
        let commonLabelY = footprints.map(\.rect.minY).min()! - 15
        footprints.forEach { footprint in
            drawFootprintBox(title: footprint.title, rect: footprint.rect, labelY: commonLabelY)
        }
    }

    private func debugFootprints(for model: StatusItemRenderModel, in previewFrame: NSRect) -> [DebugPreviewFootprint] {
        if model.showsDashboard {
            return dashboardFootprints(for: model, in: previewFrame)
        }

        let title: String
        switch model.presentation.mode {
        case .icon:
            title = "ICON"
        case .singleMetric:
            title = "TEMP"
        default:
            title = "LINE"
        }

        return [DebugPreviewFootprint(title: title, rect: previewFrame)]
    }

    private func dashboardFootprints(for model: StatusItemRenderModel, in previewFrame: NSRect) -> [DebugPreviewFootprint] {
        let contentRect = previewFrame.insetBy(dx: 4, dy: 2)
        let moduleY = contentRect.minY + 1
        let temperatureModuleWidth: CGFloat = 14 + 4 + 21
        let moduleSpacing: CGFloat = 8
        let temperatureTrailingSpacing: CGFloat = 5
        let networkTrailingSpacing: CGFloat = 5
        var x = contentRect.minX
        var footprints: [DebugPreviewFootprint] = []

        for module in model.dashboardModules {
            switch module {
            case .temperature:
                footprints.append(
                    DebugPreviewFootprint(
                        title: "TEMP",
                        rect: NSRect(x: x, y: moduleY - 1, width: temperatureModuleWidth, height: 21)
                    )
                )
                x += temperatureModuleWidth
            case .cpu:
                footprints.append(
                    DebugPreviewFootprint(
                        title: "CPU",
                        rect: NSRect(x: x, y: moduleY, width: 25, height: 16)
                    )
                )
                x += 25
            case .memory:
                footprints.append(
                    DebugPreviewFootprint(
                        title: "MEM",
                        rect: NSRect(x: x, y: moduleY, width: 25, height: 16)
                    )
                )
                x += 25
            case .network:
                footprints.append(
                    DebugPreviewFootprint(
                        title: "NET",
                        rect: NSRect(x: x, y: moduleY - 0.6, width: 58, height: 18.4)
                    )
                )
                x += 58
            }

            if module != model.dashboardModules.last {
                if module == .temperature {
                    x += temperatureTrailingSpacing
                } else if module == .network {
                    x += networkTrailingSpacing
                } else {
                    x += moduleSpacing
                }
            }
        }

        return footprints
    }

    private func drawFootprintBox(title: String, rect: NSRect, labelY: CGFloat) {
        let pathRect = rect.insetBy(dx: -3, dy: -3)
        let path = NSBezierPath(roundedRect: pathRect, xRadius: 9, yRadius: 9)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let titleSize = NSAttributedString(string: title, attributes: attributes).size()
        let labelWidth = max(32, ceil(titleSize.width) + 10)
        let labelRect = NSRect(
            x: rect.midX - (labelWidth / 2),
            y: labelY,
            width: labelWidth,
            height: 12
        )
        NSColor.controlBackgroundColor.setFill()
        labelRect.fill()

        let textPoint = CGPoint(
            x: labelRect.minX + floor((labelRect.width - titleSize.width) / 2),
            y: labelRect.minY + floor((labelRect.height - titleSize.height) / 2) - 0.5
        )
        title.draw(at: textPoint, withAttributes: attributes)
    }

    private func drawDashedLine(from start: CGPoint, to end: CGPoint, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        color.setStroke()
        path.stroke()
    }

}

struct StatusBarPreviewRepresentable: NSViewRepresentable {
    let settings: FluxBarSettings
    let monitor: SystemMonitor

    func makeNSView(context: Context) -> StatusBarPreviewContainerView {
        let view = StatusBarPreviewContainerView(frame: .zero)
        view.configure(settings: settings, monitor: monitor)
        return view
    }

    func updateNSView(_ nsView: StatusBarPreviewContainerView, context: Context) {
        nsView.configure(settings: settings, monitor: monitor)
    }
}

private struct MeterDrawSpec {
    let label: String
    let ratio: Double?
    let tint: NSColor
}

private struct VerticalLabelLayout {
    let attributes: [NSAttributedString.Key: Any]
    let lineHeight: CGFloat
    let glyphHeight: CGFloat
    let originY: CGFloat

    var visibleHeight: CGFloat {
        glyphHeight + (lineHeight * 2)
    }
}

private struct DebugPreviewFootprint {
    let title: String
    let rect: NSRect
}

private final class StatusLineLabel: NSTextField {
    var text: String = "" {
        didSet {
            stringValue = text
        }
    }

    init() {
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        drawsBackground = false
        font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        textColor = .labelColor
        stringValue = ""
        lineBreakMode = .byClipping
        usesSingleLineMode = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class StatusMeterView: NSView {
    private var value: Double?
    private var tint: NSColor = .systemBlue
    private var unavailable = false

    func configure(value: Double?, tint: NSColor, unavailable: Bool) {
        self.value = value
        self.tint = tint
        self.unavailable = unavailable
        needsDisplay = true
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        capsule.fill()

        if let value {
            let clamped = min(max(value, 0), 1)
            let fillHeight = 3 + ((rect.height - 4) * clamped)
            let fillRect = NSRect(
                x: rect.minX + 1,
                y: rect.maxY - fillHeight - 1,
                width: rect.width - 2,
                height: fillHeight
            )
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: fillRect.width / 2, yRadius: fillRect.width / 2)
            tint.setFill()
            fillPath.fill()
        } else if unavailable {
            let dashed = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
            dashed.lineWidth = 1
            dashed.setLineDash([2, 2], count: 2, phase: 0)
            NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
            dashed.stroke()
        }
    }
}
