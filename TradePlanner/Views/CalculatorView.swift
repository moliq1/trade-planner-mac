import Foundation
import SwiftUI

struct CalculatorView: View {
    let planID: UUID?
    let compact: Bool

    @EnvironmentObject private var store: PlanStore
    @Environment(\.openWindow) private var openWindow
    @State private var draft = TradeDraft()
    @State private var editingPlanID: UUID?
    @State private var message = ""
    @State private var showMessage = false

    private var preview: Result<TradeCalculation, Error> {
        Result { try TradeCalculator.calculate(draft.calculationInput()) }
    }

    private var result: TradeCalculation? { try? preview.get() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(.tint)
                    Text(editingPlanID == nil ? "新建交易计划" : "编辑交易计划")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        openWindow(id: "history")
                    } label: {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    labeledTextField("股票代码", placeholder: "601899 / 02899.HK", text: $draft.symbol)
                    labeledTextField("股票名称", placeholder: "选填", text: $draft.companyName)
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("市场").font(.caption).foregroundStyle(.secondary)
                        Picker("市场", selection: $draft.market) {
                            ForEach(TradeMarket.allCases) { market in
                                Text(market.title).tag(market)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .onChange(of: draft.market) { market in
                            draft.currencyCode = market.defaultCurrency
                            draft.lotSizeText = market.defaultLotSize
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("币种（不自动换汇）").font(.caption).foregroundStyle(.secondary)
                        Picker("币种", selection: $draft.currencyCode) {
                            ForEach(["CNY", "HKD", "USD"], id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }

                labeledTextField("计划买入价", placeholder: "例如 100", text: $draft.entryText)

                VStack(alignment: .leading, spacing: 9) {
                    modeHeader("止损", mode: stopModeBinding)
                    TextField(draft.stopMode == .price ? "止损价格" : "亏损百分比（%）", text: $draft.stopText)
                        .textFieldStyle(.roundedBorder)
                    if let result {
                        HStack {
                            Text("止损价  \(DecimalText.display(result.stopPrice, places: 4))")
                            Spacer()
                            Text("−\(DecimalText.display(result.stopLossPercentage))%")
                                .foregroundStyle(.red)
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
                .padding(11)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 9) {
                    modeHeader("止盈", mode: targetModeBinding)
                    TextField(draft.targetMode == .price ? "止盈价格" : "盈利百分比（%）", text: $draft.targetText)
                        .textFieldStyle(.roundedBorder)
                    if let result {
                        HStack {
                            Text("止盈价  \(DecimalText.display(result.targetPrice, places: 4))")
                            Spacer()
                            Text("+\(DecimalText.display(result.targetGainPercentage))%")
                                .foregroundStyle(.green)
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
                .padding(11)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                if let result {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("预期收益 / 风险")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(DecimalText.display(result.rewardRiskRatio)) R")
                                .font(.system(size: 29, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("理论盈亏平衡胜率")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(DecimalText.display(result.breakEvenWinRate))%")
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                } else if case .failure(let error) = preview {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                DisclosureGroup("仓位与风险预算") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            labeledTextField("账户资金", placeholder: "可留空", text: $draft.capitalText)
                            labeledTextField("最大单笔风险 %", placeholder: "例如 1", text: $draft.riskText)
                            labeledTextField("每手股数", placeholder: "如 100", text: $draft.lotSizeText)
                        }
                        if let result, let quantity = result.suggestedQuantity {
                            HStack(alignment: .top) {
                                metric("参考数量", "\(quantity) 股")
                                Spacer(minLength: 4)
                                metric("计划亏损", "−\(DecimalText.display(result.plannedLoss ?? 0))")
                                Spacer(minLength: 4)
                                metric("计划盈利", "+\(DecimalText.display(result.plannedGain ?? 0))")
                            }
                            .font(.caption.monospacedDigit())
                            if quantity == 0 {
                                Text("风险预算或现金不足以买入一手。")
                                    .foregroundStyle(.orange).font(.caption)
                            }
                        }
                    }
                    .padding(.top, 9)
                }
                .font(.subheadline.weight(.medium))

                HStack {
                    Text("状态").font(.caption).foregroundStyle(.secondary)
                    Picker("状态", selection: $draft.status) {
                        ForEach(PlanStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .labelsHidden()
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("买入依据与失效条件").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(height: compact ? 54 : 105)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1))
                }

                HStack {
                    Button {
                        savePlan()
                    } label: {
                        Label(editingPlanID == nil ? "保存计划" : "保存修改", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(result == nil)

                    Button("清空") {
                        editingPlanID = nil
                        draft = TradeDraft()
                    }
                    .buttonStyle(.bordered)
                }
                Text("仅做多 · 未计税费与滑点 · 非交易建议 · 港股每手股数请按标的修改")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .task(id: planID) { loadPlan() }
        .alert("交易计划助手", isPresented: $showMessage) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private func labeledTextField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text(value).bold()
        }
    }

    private func modeHeader(_ title: String, mode: Binding<PriceInputMode>) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Picker("输入方式", selection: mode) {
                Text("百分比").tag(PriceInputMode.percentage)
                Text("价格").tag(PriceInputMode.price)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var stopModeBinding: Binding<PriceInputMode> {
        Binding(get: { draft.stopMode }, set: { nextMode in
            if let result, nextMode != draft.stopMode {
                draft.stopText = DecimalText.display(
                    nextMode == .price ? result.stopPrice : result.stopLossPercentage,
                    places: 8
                )
            }
            draft.stopMode = nextMode
        })
    }

    private var targetModeBinding: Binding<PriceInputMode> {
        Binding(get: { draft.targetMode }, set: { nextMode in
            if let result, nextMode != draft.targetMode {
                draft.targetText = DecimalText.display(
                    nextMode == .price ? result.targetPrice : result.targetGainPercentage,
                    places: 8
                )
            }
            draft.targetMode = nextMode
        })
    }

    private func loadPlan() {
        guard let id = planID else { return }
        guard let plan = store.plans.first(where: { $0.id == id }) else {
            present("该计划不存在或已删除。")
            return
        }
        editingPlanID = plan.id
        draft = TradeDraft(from: plan)
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
