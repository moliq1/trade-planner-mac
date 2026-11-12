import SwiftUI
import SwiftData

@main
struct TradePlannerApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TradePlan.self)
        } catch {
            // Never silently fall back to memory-only mode: doing so could lose trading plans.
            fatalError("Unable to open TradePlanner persistent store: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra("交易计划助手", systemImage: "chart.xyaxis.line") {
            CalculatorView(planID: nil, compact: true)
                .frame(width: 440, height: 650)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)

        Window("交易计划历史", id: "history") {
            HistoryView()
                .frame(minWidth: 780, minHeight: 530)
                .modelContainer(modelContainer)
        }

        WindowGroup("编辑交易计划", id: "editor", for: UUID.self) { $planID in
            CalculatorView(planID: planID, compact: false)
                .frame(minWidth: 490, minHeight: 650)
                .modelContainer(modelContainer)
        }

        Settings {
            VStack(alignment: .leading, spacing: 10) {
                Text("交易计划助手").font(.title2.bold())
                Text("完全本地运行 · 无需行情 API 或登录账户")
                Text("目前仅支持股票做多计划，计算不包含交易费用和滑点。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 440)
        }
    }
}
