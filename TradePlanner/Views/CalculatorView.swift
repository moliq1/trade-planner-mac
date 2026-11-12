import Foundation
import SwiftUI
import AppKit

/// Menu-bar calculator, macOS 13+. Price and percent fields are always visible.
/// The last edited field is the source of truth, so editing entry price is predictable.
struct CalculatorView: View {
    let planID: UUID?
    let compact: Bool

    @EnvironmentObject private var store: PlanStore
    @EnvironmentObject private var windowCoordinator: HistoryWindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var draft = TradeDraft()
    @State private var editingPlanID: UUID?
    @State private var stopPriceText = ""
    @State private var stopPercentText = "5"
    @State private var targetPriceText = ""
    @State private var targetPercentText = "15"
    @State private var message = ""
    @State private var showMessage = false

    private let profitColor = Color(red: 0.83, green: 0.28, blue: 0.31)
    private let lossColor = Color(red: 0.12, green: 0.58, blue: 0.39)
    private let cobalt = Color(red: 0.19, green: 0.44, blue: 0.94)

    private var preview: Result<TradeCalculation, Error> {
        Result { try TradeCalculator.calculate(draft.calculationInput()) }
    }
    private var result: TradeCalculation? { try? preview.get() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                identityCard
                entryCard
                stopCard
                targetCard

                if let result {
                    outcomeCard(result)
                } else if case .failure(let error) = preview {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundColor(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                riskSettings

                HStack(spacing: 10) {
                    Text("状态").font(.caption).foregroundColor(.secondary)
                    Picker("状态", selection: $draft.status) {
                        ForEach(PlanStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .labelsHidden()
                    Spacer()
                }
                .padding(.horizontal, 3)

                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("交易理由 / 失效条件", icon: "text.alignleft")
                    TextEditor(text: $draft.notes)
                        .font(.callout)
                        .frame(height: compact ? 54 : 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }

                HStack(spacing: 10) {
                    Button(action: savePlan) {
                        Label(editingPlanID == nil ? "保存交易计划" : "保存修改",
                              systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(cobalt)
                    .controlSize(.large)
                    .disabled(result == nil)

                    Button("重置") {
                        editingPlanID = nil
                        draft = TradeDraft()
                        refreshLinkedFields()
                    }
                    .controlSize(.large)
                }
                Text("仅做多 · 金额未计税费/滑点 · 止损可能无法按计划价成交")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(17)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: refreshLinkedFields)
        .onChange(of: draft.entryText) { _ in refreshLinkedFields() }
        .task(id: planID) { loadPlan() }
        .alert("交易计划助手", isPresented: $showMessage) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Spacer()
            Button {
                windowCoordinator.showHistory(openWindow: openWindow, dismissMenu: compact)
            } label: {
                Label("历史", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.bottom, 2)
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                textInput("股票代码", placeholder: "601899 / 02899.HK", text: $draft.symbol)
                textInput("股票名称", placeholder: "选填", text: $draft.companyName)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("交易市场")
                    Picker("交易市场", selection: $draft.market) {
                        Text("A 股").tag(TradeMarket.chinaA)
                        Text("港股").tag(TradeMarket.hongKong)
                    }
                    .labelsHidden()
                    .onChange(of: draft.market) { newMarket in
                        draft.currencyCode = newMarket.defaultCurrency
                        draft.lotSizeText = newMarket.defaultLotSize
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("报价与人民币结算")
                    Text(draft.market == .hongKong ? "港币报价 · 人民币金额" : "人民币报价 · 人民币金额")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if draft.market == .hongKong {
                VStack(alignment: .leading, spacing: 5) {
                    textInput("港币兑人民币（1 HKD = ? CNY）",
                              placeholder: TradeDraft.defaultHKDToCNY,
                              text: $draft.hkdToCnyText)
                    Text("默认 2026-11-12 央行中间价 0.85633 · 固定参考，可修改；与港股通实际结算汇率不同")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .panel()
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("买入计划", icon: "arrow.down.left", tint: cobalt)
            textInput(draft.market == .hongKong ? "计划买入价（港币/股）" : "计划买入价（人民币/股）",
                      placeholder: "例如 168.10", text: $draft.entryText)
            textInput("计划买入股数（选填）", placeholder: "输入股数后计算本笔金额与风险",
                      text: $draft.enteredQuantityText)
        }
        .panel()
    }

    private var stopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("止损", icon: "arrow.down.right", tint: lossColor)
            HStack(spacing: 10) {
                textInput(draft.market == .hongKong ? "止损价（HKD）" : "止损价（CNY）", placeholder: "输入价格", text: stopPriceBinding)
                textInput("亏损比例 %", placeholder: "输入百分比", text: stopPercentBinding)
            }
            Slider(value: stopSliderValue, in: 0.5...40, step: 0.5)
                .tint(lossColor)
                .accessibilityLabel("止损百分比滑块")
            HStack {
                Text("0.5%")
                Spacer()
                Text("可拖动滑块，也可直接修改两个输入框")
                Spacer()
                Text("40%")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            Divider()
            priceOutcome("止损后预计亏损", amount: result?.enteredLoss, isProfit: false)
        }
        .panel()
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("止盈", icon: "arrow.up.right", tint: profitColor)
            HStack(spacing: 10) {
                textInput(draft.market == .hongKong ? "止盈价（HKD）" : "止盈价（CNY）", placeholder: "输入价格", text: targetPriceBinding)
                textInput("盈利比例 %", placeholder: "输入百分比", text: targetPercentBinding)
            }
            Slider(value: targetSliderValue, in: 1...100, step: 1)
                .tint(profitColor)
                .accessibilityLabel("止盈百分比滑块")
            HStack {
                Text("1%")
                Spacer()
                Text("超出滑块范围也可以手动输入")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            Divider()
            priceOutcome("止盈后预计盈利", amount: result?.enteredGain, isProfit: true)
        }
        .panel()
    }

    private func outcomeCard(_ value: TradeCalculation) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("预期盈亏比")
                    Text("\(DecimalText.display(value.rewardRiskRatio)) R")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundColor(profitColor)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    fieldLabel("盈亏平衡胜率（理论）")
                    Text("\(DecimalText.display(value.breakEvenWinRate))%")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            GeometryReader { geom in
                HStack(spacing: 4) {
                    Capsule().fill(lossColor)
                        .frame(width: max(4, (geom.size.width - 4) /
                                          (1 + min(max(decimalDouble(value.rewardRiskRatio), 0.01), 100))))
                    Capsule().fill(profitColor)
                }
            }
            .frame(height: 7)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 14).fill(cobalt.opacity(0.065)))
    }

    private var riskSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("本笔仓位与风险（人民币）",
                         icon: "shield.lefthalf.filled", tint: cobalt)
            HStack(spacing: 10) {
                textInput("总本金（CNY）", placeholder: "1500000", text: $draft.capitalText)
                textInput("单笔风险上限（%）", placeholder: "1", text: $draft.riskText)
            }
            if let value = result {
                HStack(spacing: 11) {
                    positionMetric("本笔买入金额", value.enteredCost.map { "¥" + DecimalText.display($0) } ?? "—",
                                   tint: .primary)
                    positionMetric("占总本金比例", value.enteredPositionPercentOfCapital.map {
                        DecimalText.display($0, places: 3) + "%"
                    } ?? "—", tint: .primary)
                }
                HStack(spacing: 11) {
                    positionMetric("到止损价的亏损", value.enteredLoss.map {
                        "−¥" + DecimalText.display($0)
                    } ?? "—", tint: lossColor)
                    positionMetric("本笔本金风险", value.enteredRiskPercentOfCapital.map {
                        DecimalText.display($0, places: 3) + "%"
                    } ?? "—", tint: value.exceedsRiskBudget == true ? .orange : lossColor)
                }
                if value.enteredQuantity == nil {
                    Label("填写上面的买入股数，即时计算本笔金额和风险占比",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if value.exceedsRiskBudget == true {
                    Label("本笔止损亏损超过风险预算", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if value.exceedsCapital == true {
                    Label("本笔买入金额超过总本金", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if let qty = value.enteredQuantity,
                   let lot = Int(draft.lotSizeText), lot > 1, qty % lot != 0 {
                    Text("注意：买入股数不是每手 \(lot) 股的整倍数")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            DisclosureGroup("参考仓位与交易单位") {
                HStack(spacing: 10) {
                    textInput("每手股数", placeholder: "100", text: $draft.lotSizeText)
                    if let value = result {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("按风险预算建议股数")
                            Text(value.suggestedQuantity.map { "\($0) 股" } ?? "—")
                                .font(.callout.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let budget = result?.riskBudget {
                    Text("单笔风险预算：¥\(DecimalText.display(budget))；仅供计划参考。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption.weight(.medium))
            Text(draft.market == .hongKong ?
                 "港股按设置的 HKD→CNY 固定汇率估算；不含结算汇差、手续费、印花税和滑点。" :
                 "A 股金额与风险均为人民币；未计佣金、税费、跳空和滑点。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panel()
    }

    private func positionMetric(_ name: String, _ amount: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(name)
            Text(amount)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.8)))
    }

    // P&L cash is CNY, including HKD-quoted stocks converted by the core engine.
    private func priceOutcome(_ title: String, amount: Decimal?, isProfit: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            fieldLabel(title + "（人民币）")
            Spacer(minLength: 5)
            if let amount = amount {
                Text((isProfit ? "+¥" : "−¥") + DecimalText.display(amount))
                    .foregroundColor(isProfit ? profitColor : lossColor)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("填入买入股数后显示")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 1)
    }

    private func sectionTitle(_ name: String, icon: String, tint: Color = .primary) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundColor(tint)
            Text(name).font(.headline)
            Spacer()
        }
    }

    private func fieldLabel(_ name: String) -> some View {
        Text(name).font(.caption).foregroundColor(.secondary)
    }

    private func textInput(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outcomeAmount(_ title: String, amount: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel(title)
            Text(amount)
                .foregroundColor(color)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(draft.currencyCode).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Editing either field synchronizes the other without reactive update loops.
    // The draft retains the original user-edit mode for future entry-price changes
    // and for lossless persistence of the last edited input.
    private var stopPriceBinding: Binding<String> {
        Binding(get: { stopPriceText }, set: { new in
            draft.stopMode = .price
            draft.stopText = new
            refreshStop()
        })
    }
    private var stopPercentBinding: Binding<String> {
        Binding(get: { stopPercentText }, set: { new in
            draft.stopMode = .percentage
            draft.stopText = new
            refreshStop()
        })
    }
    private var targetPriceBinding: Binding<String> {
        Binding(get: { targetPriceText }, set: { new in
            draft.targetMode = .price
            draft.targetText = new
            refreshTarget()
        })
    }
    private var targetPercentBinding: Binding<String> {
        Binding(get: { targetPercentText }, set: { new in
            draft.targetMode = .percentage
            draft.targetText = new
            refreshTarget()
        })
    }

    private var stopSliderValue: Binding<Double> {
        Binding(get: {
            min(40, max(0.5, decimalDouble(DecimalText.parse(stopPercentText) ?? 5)))
        }, set: { value in
            draft.stopMode = .percentage
            draft.stopText = String(format: "%.1f", value)
            refreshStop()
        })
    }
    private var targetSliderValue: Binding<Double> {
        Binding(get: {
            min(100, max(1, decimalDouble(DecimalText.parse(targetPercentText) ?? 15)))
        }, set: { value in
            draft.targetMode = .percentage
            draft.targetText = String(format: "%.0f", value)
            refreshTarget()
        })
    }
    private func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func refreshLinkedFields() {
        refreshStop()
        refreshTarget()
    }

    private func refreshStop() {
        guard let entry = DecimalText.parse(draft.entryText), entry > 0 else {
            if draft.stopMode == .price {
                stopPriceText = draft.stopText; stopPercentText = ""
            } else {
                stopPercentText = draft.stopText; stopPriceText = ""
            }
            return
        }
        switch draft.stopMode {
        case .price:
            stopPriceText = draft.stopText
            if let price = DecimalText.parse(draft.stopText) {
                stopPercentText = DecimalText.display((entry - price) / entry * 100, places: 4)
            } else {
                stopPercentText = ""
            }
        case .percentage:
            stopPercentText = draft.stopText
            if let percent = DecimalText.parse(draft.stopText) {
                stopPriceText = DecimalText.display(entry * (1 - percent / 100), places: 4)
            } else {
                stopPriceText = ""
            }
        }
    }

    private func refreshTarget() {
        guard let entry = DecimalText.parse(draft.entryText), entry > 0 else {
            if draft.targetMode == .price {
                targetPriceText = draft.targetText; targetPercentText = ""
            } else {
                targetPercentText = draft.targetText; targetPriceText = ""
            }
            return
        }
        switch draft.targetMode {
        case .price:
            targetPriceText = draft.targetText
            if let price = DecimalText.parse(draft.targetText) {
                targetPercentText = DecimalText.display((price - entry) / entry * 100, places: 4)
            } else {
                targetPercentText = ""
            }
        case .percentage:
            targetPercentText = draft.targetText
            if let percent = DecimalText.parse(draft.targetText) {
                targetPriceText = DecimalText.display(entry * (1 + percent / 100), places: 4)
            } else {
                targetPriceText = ""
            }
        }
    }

    private func loadPlan() {
        guard let id = planID else { return }
        guard let plan = store.plans.first(where: { $0.id == id }) else {
            present("该计划不存在或已删除。")
            return
        }
        editingPlanID = plan.id
        draft = TradeDraft(from: plan)
        refreshLinkedFields()
    }

    private func savePlan() {
        guard !draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              !draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            present("请至少填写股票代码或股票名称，以便之后查找。")
            return
        }
        do {
            let calculation = try TradeCalculator.calculate(draft.calculationInput())
            editingPlanID = try store.save(
                draft: draft, calculation: calculation, editingID: editingPlanID
            )
            present("交易计划已保存在这台 Mac 上。")
        } catch {
            present("保存失败：\(error.localizedDescription)")
        }
    }

    private func present(_ text: String) {
        message = text
        showMessage = true
    }
}

// Subtle native-looking panel with adaptive light/dark colors.
private struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(Color.primary.opacity(0.075), lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func panel() -> some View { modifier(PanelModifier()) }
}
