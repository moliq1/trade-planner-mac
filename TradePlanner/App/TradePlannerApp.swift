import SwiftUI

@main
struct TradePlannerApp: App {
    @StateObject private var store = PlanStore()

    var body: some Scene {
        MenuBarExtra("交易计划助手", systemImage: "chart.xyaxis.line") {
            CalculatorView(planID: nil, compact: true)
                .frame(width: 440, height: 650)
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window("交易计划历史", id: "history") {
            HistoryView()
                .frame(minWidth: 780, minHeight: 530)
                .environmentObject(store)
        }

        WindowGroup("编辑交易计划", id: "editor", for: UUID.self) { $planID in
            CalculatorView(planID: planID, compact: false)
                .frame(minWidth: 490, minHeight: 650)
                .environmentObject(store)
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
