import SwiftUI
import AppKit

@main
struct TradePlannerApp: App {
    @StateObject private var store = PlanStore()
    @StateObject private var windows = HistoryWindowCoordinator()

    var body: some Scene {
        MenuBarExtra("交易计划助手", systemImage: "chart.xyaxis.line") {
            CalculatorView(planID: nil, compact: true)
                .frame(width: 482, height: 720)
                .environmentObject(store)
                .environmentObject(windows)
                .background(WindowCapture { window in windows.registerMenu(window) })
        }
        .menuBarExtraStyle(.window)

        Window("交易计划历史", id: "history") {
            HistoryView()
                .frame(minWidth: 780, minHeight: 530)
                .environmentObject(store)
                .background(WindowCapture { window in windows.registerHistory(window) })
        }

        WindowGroup("编辑交易计划", id: "editor", for: UUID.self) { $planID in
            CalculatorView(planID: planID, compact: false)
                .frame(minWidth: 520, minHeight: 720)
                .environmentObject(store)
                .environmentObject(windows)
        }

        Settings {
            VStack(alignment: .leading, spacing: 10) {
                Text("交易计划助手").font(.title2.bold())
                Text("支持 macOS 13 · 计划保存在本机 Application Support")
                Text("目前仅支持股票做多计划，计算不包含交易费用和滑点。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 440)
        }
    }
}


// macOS 13 has no public SwiftUI binding for MenuBarExtra window visibility.
// Capture the owned NSWindows and coordinate focus without private API.
final class HistoryWindowCoordinator: ObservableObject {
    weak var menuWindow: NSWindow?
    weak var historyWindow: NSWindow?
    private var pendingHistoryFocus = false

    func registerMenu(_ window: NSWindow) {
        menuWindow = window
    }

    func registerHistory(_ window: NSWindow) {
        historyWindow = window
        focusHistoryIfNeeded()
    }

    func showHistory(openWindow: OpenWindowAction, dismissMenu: Bool) {
        pendingHistoryFocus = true
        if dismissMenu {
            menuWindow?.orderOut(nil)
        }
        openWindow(id: "history")
        NSApp.activate(ignoringOtherApps: true)
        focusHistoryIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.focusHistoryIfNeeded()
        }
    }

    private func focusHistoryIfNeeded() {
        guard pendingHistoryFocus, let window = historyWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pendingHistoryFocus = false
    }
}

// NSViewRepresentable reports its SwiftUI scene's NSWindow.
private final class CapturedWindowView: NSView {
    var onAttached: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            onAttached?(window)
        }
    }
}

private struct WindowCapture: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> CapturedWindowView {
        let view = CapturedWindowView(frame: .zero)
        view.onAttached = onWindow
        return view
    }

    func updateNSView(_ view: CapturedWindowView, context: Context) {
        view.onAttached = onWindow
        if let window = view.window {
            onWindow(window)
        }
    }
}
