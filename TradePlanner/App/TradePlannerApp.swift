import AppKit
import SwiftUI

@main
struct TradePlannerApp: App {
    @NSApplicationDelegateAdaptor(TradePlannerDelegate.self) private var delegate

    var body: some Scene {
        // This is a menu bar utility; windows and the status item are managed
        // through AppKit to support left/right mouse clicks on macOS 13.
        Settings {
            VStack(alignment: .leading, spacing: 10) {
                Text("交易计划助手").font(.title2.bold())
                Text("支持 macOS 13 · 本地保存于 Application Support")
                Text("菜单栏左键：打开计算器；右键：历史记录 / 退出应用")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 430)
        }
    }
}

private final class TradePlannerServices {
    static let shared = TradePlannerServices()
    let store = PlanStore()
    lazy var windows = HistoryWindowCoordinator(store: store)
}

final class TradePlannerDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: TradePlannerStatusBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already configures the app as an agent.
        // Do not change the activation policy after SwiftUI has launched.
        let services = TradePlannerServices.shared
        statusBarController = TradePlannerStatusBar(
            store: services.store,
            coordinator: services.windows
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Mission Control and Dock activation do not call the menu bar button.
        DispatchQueue.main.async {
            TradePlannerServices.shared.windows.restoreWindowOnAppActivation()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        return false
    }
}

// NSStatusItem gives us two unambiguous mouse actions. SwiftUI MenuBarExtra
// intentionally does not expose a separate right-click context menu.
private final class TradePlannerStatusBar: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let coordinator: HistoryWindowCoordinator

    init(store: PlanStore, coordinator: HistoryWindowCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let content = CalculatorView(planID: nil, compact: true)
            .frame(width: 482, height: 720)
            .environmentObject(store)
            .environmentObject(coordinator)
        popover.contentViewController = NSHostingController(rootView: content)
        popover.contentSize = NSSize(width: 482, height: 720)
        popover.behavior = .transient

        coordinator.dismissPopover = { [weak popover] in
            popover?.performClose(nil)
        }

        if let button = statusItem.button {
            let icon = NSImage(
                systemSymbolName: "chart.xyaxis.line",
                accessibilityDescription: "交易计划助手"
            )
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "左键：交易计算器  ·  右键：历史与退出"
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.type == .rightMouseDown {
            showContextMenu(for: sender, event: event)
        } else {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        }
    }

    private func showContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        let history = menu.addItem(
            withTitle: "历史记录",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        history.target = self
        history.image = NSImage(systemSymbolName: "clock.arrow.circlepath",
                                accessibilityDescription: nil)
        menu.addItem(.separator())
        let exit = menu.addItem(
            withTitle: "退出 TradePlanner",
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        exit.target = self
        exit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func openHistory() {
        // NSMenu actions fire while the menu is still tracking. Delay window
        // activation until after the context menu has fully dismissed.
        DispatchQueue.main.async { [weak self] in
            self?.coordinator.showHistory(dismissMenu: true)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

final class HistoryWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    private let store: PlanStore
    private var historyWindow: NSWindow?
    private var editorWindows: [UUID: NSWindow] = [:]
    var dismissPopover: (() -> Void)?

    init(store: PlanStore) {
        self.store = store
        super.init()
    }

    func showHistory(dismissMenu: Bool = true) {
        // The left-click popover button and right-click NSMenu both arrive
        // while an interactive menu/popup is active. Closing the popup and
        // synchronously opening a window can leave it hidden behind other apps
        // on macOS 13. Always finish dismissal first.
        if dismissMenu { dismissPopover?() }
        DispatchQueue.main.async { [weak self] in
            self?.presentHistoryWindow()
        }
    }

    private func presentHistoryWindow() {
        if historyWindow == nil {
            let content = HistoryView()
                .environmentObject(store)
                .environmentObject(self)
            historyWindow = makeWindow(
                title: "交易计划历史",
                width: 1080,
                height: 700,
                minimumContentSize: NSSize(width: 820, height: 530),
                frameAutosaveName: "TradePlanner.HistoryWindow.Frame.v1",
                rootView: content
            )
        }
        activate(historyWindow)
    }

    func showEditor(planID: UUID) {
        if let existing = editorWindows[planID] {
            activate(existing)
            return
        }
        let content = CalculatorView(planID: planID, compact: false)
            .frame(minWidth: 520, minHeight: 720)
            .environmentObject(store)
            .environmentObject(self)
        let window = makeWindow(
            title: "编辑交易计划",
            width: 560,
            height: 770,
            rootView: content
        )
        editorWindows[planID] = window
        activate(window)
    }

    private func makeWindow<Content: View>(
        title: String,
        width: CGFloat,
        height: CGFloat,
        minimumContentSize: NSSize = NSSize(width: 500, height: 600),
        frameAutosaveName: String? = nil,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior.insert(.moveToActiveSpace)

        let hostingController = NSHostingController(rootView: rootView)
        // Avoid SwiftUI's automatic resizing of the AppKit window whenever
        // NavigationSplitView recalculates its intrinsic content size.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.contentMinSize = minimumContentSize

        // Set the requested size AFTER installing the SwiftUI controller.
        // Cap the default to the available display area on smaller Macs.
        let visible = NSScreen.main?.visibleFrame
        let initialSize = NSSize(
            width: min(width, max(minimumContentSize.width, (visible?.width ?? width) - 40)),
            height: min(height, max(minimumContentSize.height, (visible?.height ?? height) - 40))
        )
        window.setContentSize(initialSize)
        window.center()

        if let name = frameAutosaveName {
            // Restore custom frame across closing/reopening and app launches.
            _ = window.setFrameUsingName(name)
            _ = window.setFrameAutosaveName(name)
            let restoredContentSize = window.contentRect(
                forFrameRect: window.frame
            ).size
            if restoredContentSize.width < minimumContentSize.width ||
               restoredContentSize.height < minimumContentSize.height {
                window.setContentSize(NSSize(
                    width: max(minimumContentSize.width, restoredContentSize.width),
                    height: max(minimumContentSize.height, restoredContentSize.height)
                ))
            }
        }
        return window
    }

    private func activate(_ window: NSWindow?) {
        guard let window = window else { return }

        // LSUIElement starts in accessory mode. Temporarily become a regular
        // Dock application while history or editor windows are open, allowing
        // Mission Control to switch focus back from a browser on macOS 13.
        if NSApp.activationPolicy() != .regular {
            let changed = NSApp.setActivationPolicy(.regular)
            if !changed {
                NSLog("TradePlanner: regular activation policy unavailable")
            }
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // AppKit may apply the activation-policy change on the next run-loop.
        DispatchQueue.main.async { [weak window] in
            guard let window = window, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // Only act when the user explicitly activates TradePlanner (Dock or F3).
    // Do not continuously steal focus while the user works in another app.
    func restoreWindowOnAppActivation() {
        guard NSApp.activationPolicy() == .regular,
              NSApp.keyWindow == nil else { return }
        let windows = [historyWindow].compactMap { $0 } + Array(editorWindows.values)
        if let front = windows.first(where: { $0.isVisible }) {
            front.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if historyWindow === closing { historyWindow = nil }
        editorWindows = editorWindows.filter { $0.value !== closing }

        // Return to menu bar-only mode after the last managed window closes.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.historyWindow == nil && self.editorWindows.isEmpty {
                let changed = NSApp.setActivationPolicy(.accessory)
                if !changed {
                    NSLog("TradePlanner: accessory activation policy unavailable")
                }
            }
        }
    }
}
