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
        // An accessory app can activate its own windows without a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        let services = TradePlannerServices.shared
        statusBarController = TradePlannerStatusBar(
            store: services.store,
            coordinator: services.windows
        )
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
        coordinator.showHistory(dismissMenu: true)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

final class HistoryWindowCoordinator: ObservableObject {
    private let store: PlanStore
    private var historyWindow: NSWindow?
    private var editorWindows: [UUID: NSWindow] = [:]
    var dismissPopover: (() -> Void)?

    init(store: PlanStore) {
        self.store = store
    }

    func showHistory(dismissMenu: Bool = true) {
        if dismissMenu { dismissPopover?() }
        if historyWindow == nil {
            let content = HistoryView()
                .environmentObject(store)
                .environmentObject(self)
            historyWindow = makeWindow(
                title: "交易计划历史",
                width: 940,
                height: 660,
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
        title: String, width: CGFloat, height: CGFloat, rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        return window
    }

    private func activate(_ window: NSWindow?) {
        guard let window = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
