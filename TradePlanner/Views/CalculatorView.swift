import Foundation
import SwiftUI

/// Menu-bar calculator, macOS 13+. Price and percent fields are always visible.
/// The last edited field is the source of truth, so editing entry price is predictable.
struct CalculatorView: View {
    let planID: UUID?
    let compact: Bool

    @EnvironmentObject private var store: PlanStore
    @Environment(\.openWindow) private var openWindow
    @State private var draft = TradeDraft()
    @State private var editingPlanID: UUID?
    @State private var stopPriceText = ""
    @State private var stopPercentText = "5"
    @State private var targetPriceText = ""
    @State private var targetPercentText = "15"
    @State private var message = ""
    @State private var showMessage = false

    private let danger = Color(red: 0.83, green: 0.28, blue: 0.31)
    private let success = Color(red: 0.12, green: 0.58, blue: 0.39)
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
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(cobalt))
            VStack(alignment: .leading, spacing: 3) {
                Text(editingPlanID == nil ? "交易计划" : "编辑交易计划")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("计算风险 · 规划盈亏 · 保存决策")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 2)
            Button {
                openWindow(id: "history")
            } label: {
                Label("历史", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
        }
        .padding(.bottom, 2)
    }

    private var identityCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                textInput("股票代码", placeholder: "601899 / 02899.HK", text: $draft.symbol)
                textInput("股票名称", placeholder: "选填", text: $draft.companyName)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("交易市场")
                    Picker("交易市场", selection: $draft.market) {
                        ForEach(TradeMarket.allCases) { market in
                            Text(market.title).tag(market)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: draft.market) { newMarket in
                        draft.currencyCode = newMarket.defaultCurrency
                        draft.lotSizeText = newMarket.defaultLotSize
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("货币")
                    Picker("货币", selection: $draft.currencyCode) {
                        ForEach(["CNY", "HKD", "USD"], id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .panel()
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("买入计划", icon: "arrow.down.left", tint: cobalt)
            textInput("计划买入价", placeholder: "例如 168.10", text: $draft.entryText)
            HStack(alignment: .bottom, spacing: 10) {
                textInput("计划买入股数（选填）", placeholder: "填股数后计算实际盈亏", text: $draft.enteredQuantityText)
                if let result, let cost = result.enteredCost {
                    VStack(alignment: .trailing, spacing: 5) {
                        fieldLabel("预计买入金额")
                        Text(DecimalText.display(cost))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text(draft.currencyCode)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(minWidth: 120, alignment: .trailing)
                    .padding(.bottom, 4)
                }
            }
        }
        .panel()
    }

    private var stopCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("止损", icon: "arrow.down.right", tint: danger)
            HStack(spacing: 10) {
                textInput("止损价格", placeholder: "输入价格", text: stopPriceBinding)
                textInput("亏损比例 %", placeholder: "输入百分比", text: stopPercentBinding)
            }
            Slider(value: stopSliderValue, in: 0.5...40, step: 0.5)
                .tint(danger)
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
        }
        .panel()
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("止盈", icon: "arrow.up.right", tint: success)
            HStack(spacing: 10) {
                textInput("止盈价格", placeholder: "输入价格", text: targetPriceBinding)
                textInput("盈利比例 %", placeholder: "输入百分比", text: targetPercentBinding)
            }
            Slider(value: targetSliderValue, in: 1...100, step: 1)
                .tint(success)
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
        }
        .panel()
    }

    private func outcomeCard(_ value: TradeCalculation) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("预期盈亏比")
                    Text("\(DecimalText.display(value.rewardRiskRatio)) R")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(success)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    fieldLabel("理论盈亏平衡胜率")
                    Text("\(DecimalText.display(value.breakEvenWinRate))%")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            GeometryReader { geom in
                HStack(spacing: 4) {
                    Capsule().fill(danger)
                        .frame(width: max(4, (geom.size.width - 4) / (1 + min(max(decimalDouble(value.rewardRiskRatio), 0.01), 100))))
                    Capsule().fill(success)
                }
            }
            .frame(height: 7)

            if let actualLoss = value.enteredLoss, let actualGain = value.enteredGain {
                HStack(spacing: 12) {
                    outcomeAmount("计划止损亏损", amount: "−\(DecimalText.display(actualLoss))",
                                  color: danger)
                    outcomeAmount("计划止盈盈利", amount: "+\(DecimalText.display(actualGain))",
                                  color: success)
                }
                Divider()
                HStack {
                    Text("本笔交易风险占总本金")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let riskPct = value.enteredRiskPercentOfCapital {
                        Text("\(DecimalText.display(riskPct, places: 3))%")
                            .font(.headline.monospacedDigit())
                            .foregroundColor(value.exceedsRiskBudget == true ? danger : .primary)
                    } else {
                        Text("请在风险设置填写总本金").font(.caption)
                    }
                }
                if value.exceedsRiskBudget == true {
                    Label("超过单笔风险预算，请调整股数或止损位置", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(danger).font(.caption)
                }
                if value.exceedsCapital == true {
                    Label("计划买入金额超过所填总本金", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(danger).font(.caption)
                }
                if let quantity = value.enteredQuantity,
                   let lot = Int(draft.lotSizeText), lot > 1, quantity % lot != 0 {
                    Text("提醒：计划股数不是 \(lot) 的整倍数，请核对交易单位。")
                        .foregroundColor(.orange).font(.caption)
                }
            } else {
                Text("在“买入股数”中填入数量，即可计算本笔计划的盈亏金额及本金风险。")
                    .foregroundColor(.secondary)
                    .font(.callout)
                if let suggested = value.suggestedQuantity {
                    HStack {
                        Text("按当前预算参考买入")
                        Spacer()
                        Text("\(suggested) 股").fontWeight(.semibold)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cobalt.opacity(0.065))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(cobalt.opacity(0.15)))
        )
    }

    private var riskSettings: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    textInput("总本金（\(draft.currencyCode)）",
                              placeholder: "1500000", text: $draft.capitalText)
                    textInput("单笔风险预算 %", placeholder: "1", text: $draft.riskText)
                    textInput("每手股数", placeholder: "100", text: $draft.lotSizeText)
                }
                if let value = result {
                    HStack(spacing: 12) {
                        compactMetric("风险预算上限",
                                      value.riskBudget.map { DecimalText.display($0) } ?? "—")
                        compactMetric("预算建议股数",
                                      value.suggestedQuantity.map { "\($0) 股" } ?? "—")
                    }
                    if let cost = value.enteredCost {
                        HStack {
                            Text("本笔占用资金")
                            Spacer()
                            Text("\(DecimalText.display(cost)) \(draft.currencyCode)")
                                .fontWeight(.semibold)
                        }
                        if let ratio = value.enteredPositionPercentOfCapital {
                            HStack {
                                Text("占账户资金")
                                Spacer()
                                Text("\(DecimalText.display(ratio, places: 2))%").fontWeight(.semibold)
                            }
                        }
                    }
                }
                Text("总本金与股票金额按同一币种计算，不自动换汇；实际止损可能因跳空或滑点超出预算。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        } label: {
            Label("仓位与风险设置", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
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
