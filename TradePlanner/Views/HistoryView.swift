import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject private var store: PlanStore
    @Environment(\.openWindow) private var openWindow
    private var plans: [TradePlan] { store.plans }

    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var showDeleteConfirmation = false
    @State private var exporting = false
    @State private var alertText = ""
    @State private var showAlert = false

    private var filteredPlans: [TradePlan] {
        guard !searchText.isEmpty else { return plans }
        return plans.filter {
            $0.symbol.localizedCaseInsensitiveContains(searchText) ||
            $0.companyName.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedPlan: TradePlan? { plans.first { $0.id == selectedID } }

    private func plans(for status: PlanStatus) -> [TradePlan] {
        filteredPlans.filter { (PlanStatus(rawValue: $0.statusRaw) ?? .planned) == status }
    }

    private func sidebarRow(_ plan: TradePlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(plan.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !plan.symbol.isEmpty {
                    Text(plan.symbol)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                sidebarPrice("买", plan.entryText, color: .primary)
                Spacer(minLength: 1)
                sidebarPrice("止", plan.stopPriceText, color: .green)
                Spacer(minLength: 1)
                sidebarPrice("盈", plan.targetPriceText, color: .red)
            }
            Text(plan.updatedAt, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func sidebarPrice(_ prefix: String, _ rawPrice: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(prefix).foregroundColor(.secondary)
            Text(displayPrice(rawPrice))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("搜索名称、代码或备注", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        exporting = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("导出当前筛选结果 CSV")
                    .disabled(filteredPlans.isEmpty)
                }
                .padding([.top, .horizontal], 12)

                if let loadError = store.loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal, 12)
                }
                List(selection: $selectedID) {
                    ForEach(PlanStatus.allCases) { status in
                        if !plans(for: status).isEmpty {
                            Section {
                                ForEach(plans(for: status)) { plan in
                                    sidebarRow(plan).tag(plan.id)
                                }
                            } header: {
                                Text("\(status.title) · \(plans(for: status).count)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史计划 · \(plans.count)")
            .frame(minWidth: 290)
        } detail: {
            if let plan = selectedPlan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(plan.displayName).font(.title2.bold())
                                Text("\(plan.symbol) · \(TradeMarket(rawValue: plan.marketRaw)?.title ?? "其他") · 报价 \(plan.currencyCode) / 金额 \(plan.settlementCurrency)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("编辑计划") {
                                openWindow(id: "editor", value: plan.id)
                            }
                            .buttonStyle(.borderedProminent)
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("删除计划")
                        }
                        HStack(spacing: 18) {
                            summaryMetric("买入价", displayPrice(plan.entryText))
                            summaryMetric("止损价", displayPrice(plan.stopPriceText), color: .green)
                            summaryMetric("止盈价", displayPrice(plan.targetPriceText), color: .red)
                        }
                        HStack(spacing: 18) {
                            summaryMetric("止损比例", "−\(displayDecimal(plan.lossPercentageText))%", color: .green)
                            summaryMetric("盈利比例", "+\(displayDecimal(plan.gainPercentageText))%", color: .red)
                            summaryMetric("盈亏比", "\(displayDecimal(plan.ratioText)) R", color: .red)
                        }
                        if plan.marketRaw == TradeMarket.hongKong.rawValue, let rate = plan.hkdToCnyText {
                            HStack {
                                Text("港币兑人民币（保存时汇率）")
                                Spacer()
                                Text("1 HKD = \(rate) CNY").fontWeight(.semibold)
                            }
                            .font(.caption)
                        }
                        if let manual = plan.enteredQuantity {
                            Divider()
                            HStack(spacing: 18) {
                                summaryMetric("计划买入股数", "\(manual) 股")
                                summaryMetric("本笔止损亏损（\(plan.settlementCurrency)）", plan.enteredLossText.map { "−\(displayMoney($0))" } ?? "—", color: .green)
                                summaryMetric("本笔止盈盈利（\(plan.settlementCurrency)）", plan.enteredGainText.map { "+\(displayMoney($0))" } ?? "—", color: .red)
                            }
                            HStack(spacing: 18) {
                                summaryMetric("买入金额（\(plan.settlementCurrency)）", plan.enteredCostText.map(displayMoney) ?? "—")
                                summaryMetric("占总本金风险", plan.riskAsCapitalPercentageText.map { "\(displayDecimal($0))%" } ?? "—")
                            }
                        }
                        if plan.statusRaw == PlanStatus.closed.rawValue {
                            Divider()
                            VStack(alignment: .leading, spacing: 12) {
                                Text("实际卖出与结果").font(.headline)
                                if let salePrice = plan.sellPriceText,
                                   let realized = plan.realizedPnLText,
                                   let pnl = DecimalText.parse(realized) {
                                    let resultColor: Color = pnl >= 0 ? .red : .green
                                    HStack(spacing: 18) {
                                        summaryMetric("实际卖出价", displayPrice(salePrice))
                                        summaryMetric("卖出总额（\(plan.settlementCurrency)）",
                                            plan.sellProceedsText.map(displayMoney) ?? "—")
                                    }
                                    HStack(spacing: 18) {
                                        summaryMetric("实际盈亏（\(plan.settlementCurrency)）",
                                            signedMoney(realized), color: resultColor)
                                        summaryMetric("实际收益率",
                                            signedPercent(plan.realizedReturnPctText), color: resultColor)
                                        summaryMetric("实际 R 倍数",
                                            signedR(plan.realizedRText), color: resultColor)
                                    }
                                    if let date = plan.closedAt {
                                        Text("结束时间：\(date.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text("按计划买入股数全部卖出、采用同一固定汇率计算；未计交易费用及结算汇差。")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Label("旧版已结束记录尚未填写实际卖出价；点击「编辑计划」补录。",
                                          systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("原始计划与失效条件").font(.headline)
                            Text(plan.notes.isEmpty ? "没有填写备注" : plan.notes)
                                .foregroundStyle(plan.notes.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 20)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("创建：\(plan.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            Text("修改：\(plan.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            Text("记录为计划快照，修改后会刷新当前计划数据。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(23)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("计划详情")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("选择一条交易计划").font(.title2.bold())
                    Text("在左侧查看历史记录；新计划从菜单栏图标创建。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("确定删除此计划？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) { deleteSelected() }
        } message: {
            Text("删除后无法恢复，建议先导出备份。")
        }
        .fileExporter(
            isPresented: $exporting,
            document: CSVDocument(plans: filteredPlans),
            contentType: .commaSeparatedText,
            defaultFilename: "trade-plans"
        ) { result in
            if case .failure(let error) = result {
                present("导出失败：\(error.localizedDescription)")
            }
        }
        .alert("交易计划助手", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: { Text(alertText) }
    }

    private func summaryMetric(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit().foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayDecimal(_ text: String) -> String {
        guard let number = DecimalText.parse(text) else { return text }
        return DecimalText.display(number, places: 2)
    }

    private func displayPrice(_ text: String) -> String {
        guard let number = DecimalText.parse(text) else { return text }
        return DecimalText.display(number, places: 4)
    }

    private func displayMoney(_ text: String) -> String {
        HistoryMoneyFormatter.format(text, grouped: true)
    }

    private func signedMoney(_ raw: String) -> String {
        guard let value = DecimalText.parse(raw) else { return raw }
        let symbol = value > 0 ? "+" : value < 0 ? "−" : ""
        let absolute = value < 0 ? -value : value
        return symbol + displayMoney(DecimalText.exact(absolute))
    }

    private func signedPercent(_ raw: String?) -> String {
        guard let raw = raw, let value = DecimalText.parse(raw) else { return "—" }
        let symbol = value > 0 ? "+" : value < 0 ? "−" : ""
        let absolute = value < 0 ? -value : value
        return symbol + DecimalText.display(absolute, places: 2) + "%"
    }

    private func signedR(_ raw: String?) -> String {
        guard let raw = raw, let value = DecimalText.parse(raw) else { return "—" }
        let symbol = value > 0 ? "+" : value < 0 ? "−" : ""
        let absolute = value < 0 ? -value : value
        return symbol + DecimalText.display(absolute, places: 2) + " R"
    }

    private func deleteSelected() {
        guard let plan = selectedPlan else { return }
        do {
            try store.delete(id: plan.id)
            selectedID = nil
        } catch {
            present("删除失败：\(error.localizedDescription)")
        }
    }

    private func present(_ text: String) {
        alertText = text
        showAlert = true
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var csv: String

    init(plans: [TradePlan]) {
        let header = ["ID", "股票代码", "名称", "市场", "币种", "计划买入价", "止损价", "止盈价",
                      "亏损比例%", "盈利比例%", "收益风险比R",
                      "输入止损模式", "输入止损值", "输入止盈模式", "输入止盈值",
                      "账户资金", "风险预算%", "每手股数", "状态", "备注", "创建时间", "更新时间",
                      "计划买入股数", "本笔预计成本", "本笔止损亏损", "本笔止盈盈利", "本笔亏损占本金%", "金额计价币种", "HKD兑CNY参考汇率",
                      "实际卖出价", "实际卖出总额(CNY)", "实际盈亏(CNY)",
                      "实际收益率%", "实际R", "结束时间"]
        // Deliberately construct the columns in small typed groups: Swift's
        // type checker struggles with a giant heterogeneous optional expression.
        let rows: [[String]] = plans.map { p -> [String] in
            var fields: [String] = [
                p.id.uuidString, p.symbol, p.companyName, p.marketRaw, p.currencyCode,
                p.entryText, p.stopPriceText, p.targetPriceText
            ]
            fields.append(contentsOf: [
                p.lossPercentageText, p.gainPercentageText, p.ratioText
            ])
            fields.append(contentsOf: [
                p.stopModeRaw, p.stopInputText, p.targetModeRaw, p.targetInputText,
                p.capitalText, p.riskText, p.lotSizeText, p.statusRaw, p.notes
            ])
            let isoDate = ISO8601DateFormatter()
            fields.append(isoDate.string(from: p.createdAt))
            fields.append(isoDate.string(from: p.updatedAt))
            fields.append(contentsOf: [
                p.enteredQuantity.map { String($0) } ?? "",
                p.enteredCostText.map { HistoryMoneyFormatter.format($0, grouped: false) } ?? "",
                p.enteredLossText.map { HistoryMoneyFormatter.format($0, grouped: false) } ?? "",
                p.enteredGainText.map { HistoryMoneyFormatter.format($0, grouped: false) } ?? "",
                p.riskAsCapitalPercentageText.flatMap { DecimalText.parse($0) }
                    .map { DecimalText.display($0, places: 2) } ?? "",
                p.settlementCurrency, p.hkdToCnyText ?? ""
            ])
            fields.append(contentsOf: [
                p.sellPriceText ?? "",
                p.sellProceedsText.map { HistoryMoneyFormatter.format($0, grouped: false) } ?? "",
                p.realizedPnLText.map { HistoryMoneyFormatter.format($0, grouped: false) } ?? "",
                p.realizedReturnPctText.flatMap { DecimalText.parse($0) }
                    .map { DecimalText.display($0, places: 2) } ?? "",
                p.realizedRText.flatMap { DecimalText.parse($0) }
                    .map { DecimalText.display($0, places: 2) } ?? "",
                p.closedAt.map { isoDate.string(from: $0) } ?? ""
            ])
            return fields
        }
        csv = ([header] + rows).map { $0.map(CSVDocument.escape).joined(separator: ",") }
            .joined(separator: "\r\n")
    }

    init(configuration: ReadConfiguration) throws {
        csv = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // UTF-8 BOM helps Excel on macOS/Windows interpret Chinese column names.
        let bom = Data([0xEF, 0xBB, 0xBF])
        return FileWrapper(regularFileWithContents: bom + Data(csv.utf8))
    }

    private static func escape(_ string: String) -> String {
        "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}


// Rounded display only: the original JSON data stays at full Decimal precision.
private enum HistoryMoneyFormatter {
    static func format(_ raw: String, grouped: Bool) -> String {
        guard let value = DecimalText.parse(raw) else { return raw }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = grouped
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? DecimalText.display(value, places: 2)
    }
}
