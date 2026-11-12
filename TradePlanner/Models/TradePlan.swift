import Foundation

enum TradeMarket: String, CaseIterable, Identifiable {
    case chinaA
    case hongKong
    case unitedStates
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .chinaA: "A 股"
        case .hongKong: "港股"
        case .unitedStates: "美股"
        case .other: "其他"
        }
    }
    var defaultCurrency: String {
        switch self {
        case .chinaA: "CNY"
        case .hongKong: "HKD"
        case .unitedStates: "USD"
        case .other: "CNY"
        }
    }
    var defaultLotSize: String {
        switch self {
        case .chinaA: "100"
        case .hongKong: "100" // Editable: HK stocks have different board lots.
        case .unitedStates, .other: "1"
        }
    }
}

enum PlanStatus: String, CaseIterable, Identifiable {
    case planned, entered, closed, cancelled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .planned: "计划中"
        case .entered: "已买入"
        case .closed: "已结束"
        case .cancelled: "已取消"
        }
    }
}

struct TradeDraft {
    var symbol = ""
    var companyName = ""
    var market: TradeMarket = .chinaA
    var currencyCode = "CNY"
    var entryText = "100"
    var stopMode: PriceInputMode = .percentage
    var stopText = "5"
    var targetMode: PriceInputMode = .percentage
    var targetText = "15"
    var capitalText = "1500000"
    var riskText = "1"
    var lotSizeText = "100"
    var enteredQuantityText = "" // Blank: do not infer a trade from recommended size.
    var status: PlanStatus = .planned
    var notes = ""

    func calculationInput() throws -> TradeCalculationInput {
        guard let entry = DecimalText.parse(entryText) else {
            throw TradeCalculationError.invalidEntry
        }
        guard let stop = DecimalText.parse(stopText) else {
            throw TradeCalculationError.invalidStop
        }
        guard let target = DecimalText.parse(targetText) else {
            throw TradeCalculationError.invalidTarget
        }
        guard let lotSize = Int(lotSizeText), lotSize > 0 else {
            throw TradeCalculationError.invalidLotSize
        }

        let capitalIsBlank = capitalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let riskIsBlank = riskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard capitalIsBlank == riskIsBlank else {
            throw capitalIsBlank ? TradeCalculationError.invalidCapital : TradeCalculationError.invalidRiskPercentage
        }
        let capital = capitalIsBlank ? nil : DecimalText.parse(capitalText)
        let risk = riskIsBlank ? nil : DecimalText.parse(riskText)
        if !capitalIsBlank && capital == nil { throw TradeCalculationError.invalidCapital }
        if !riskIsBlank && risk == nil { throw TradeCalculationError.invalidRiskPercentage }

        let trimmedQuantity = enteredQuantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredQuantity: Int?
        if trimmedQuantity.isEmpty {
            enteredQuantity = nil
        } else {
            guard let qty = Int(trimmedQuantity), qty > 0 else {
                throw TradeCalculationError.invalidEnteredQuantity
            }
            enteredQuantity = qty
        }
        return TradeCalculationInput(
            entryPrice: entry,
            stopInput: stop,
            stopMode: stopMode,
            targetInput: target,
            targetMode: targetMode,
            accountCapital: capital,
            riskPercentage: risk,
            lotSize: lotSize,
            enteredQuantity: enteredQuantity
        )
    }

    init() {}

    init(from plan: TradePlan) {
        symbol = plan.symbol
        companyName = plan.companyName
        market = TradeMarket(rawValue: plan.marketRaw) ?? .other
        currencyCode = plan.currencyCode
        entryText = plan.entryText
        stopMode = PriceInputMode(rawValue: plan.stopModeRaw) ?? .percentage
        stopText = plan.stopInputText
        targetMode = PriceInputMode(rawValue: plan.targetModeRaw) ?? .percentage
        targetText = plan.targetInputText
        capitalText = plan.capitalText
        riskText = plan.riskText
        lotSizeText = plan.lotSizeText
        enteredQuantityText = plan.enteredQuantity.map(String.init) ?? ""
        status = PlanStatus(rawValue: plan.statusRaw) ?? .planned
        notes = plan.notes
    }
}

struct TradePlan: Identifiable, Codable {
    var id: UUID
    var symbol: String
    var companyName: String
    var marketRaw: String
    var currencyCode: String

    // Store original editable inputs and also a frozen snapshot of derived values.
    // Decimal text is persisted losslessly instead of rounded display doubles.
    var entryText: String
    var stopModeRaw: String
    var stopInputText: String
    var targetModeRaw: String
    var targetInputText: String
    var capitalText: String
    var riskText: String
    var lotSizeText: String

    var stopPriceText: String
    var targetPriceText: String
    var lossPercentageText: String
    var gainPercentageText: String
    var ratioText: String
    var quantity: Int?
    var plannedLossText: String?
    var plannedGainText: String?
    // Optional for backward-compatible reading of JSON records saved before this update.
    var enteredQuantity: Int?
    var enteredCostText: String?
    var enteredLossText: String?
    var enteredGainText: String?
    var riskAsCapitalPercentageText: String?

    var statusRaw: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(draft: TradeDraft, calculation: TradeCalculation) {
        id = UUID()
        symbol = ""
        companyName = ""
        marketRaw = ""
        currencyCode = ""
        entryText = ""
        stopModeRaw = ""
        stopInputText = ""
        targetModeRaw = ""
        targetInputText = ""
        capitalText = ""
        riskText = ""
        lotSizeText = ""
        stopPriceText = ""
        targetPriceText = ""
        lossPercentageText = ""
        gainPercentageText = ""
        ratioText = ""
        quantity = nil
        plannedLossText = nil
        plannedGainText = nil
        enteredQuantity = nil
        enteredCostText = nil
        enteredLossText = nil
        enteredGainText = nil
        riskAsCapitalPercentageText = nil
        statusRaw = ""
        notes = ""
        createdAt = .now
        updatedAt = .now
        apply(draft: draft, calculation: calculation)
    }

    mutating func apply(draft: TradeDraft, calculation: TradeCalculation) {
        symbol = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        companyName = draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        marketRaw = draft.market.rawValue
        currencyCode = draft.currencyCode
        entryText = DecimalText.exact(calculation.entryPrice)
        stopModeRaw = draft.stopMode.rawValue
        stopInputText = draft.stopText
        targetModeRaw = draft.targetMode.rawValue
        targetInputText = draft.targetText
        capitalText = draft.capitalText
        riskText = draft.riskText
        lotSizeText = draft.lotSizeText
        stopPriceText = DecimalText.exact(calculation.stopPrice)
        targetPriceText = DecimalText.exact(calculation.targetPrice)
        lossPercentageText = DecimalText.exact(calculation.stopLossPercentage)
        gainPercentageText = DecimalText.exact(calculation.targetGainPercentage)
        ratioText = DecimalText.exact(calculation.rewardRiskRatio)
        quantity = calculation.suggestedQuantity
        plannedLossText = calculation.plannedLoss.map(DecimalText.exact)
        plannedGainText = calculation.plannedGain.map(DecimalText.exact)
        enteredQuantity = calculation.enteredQuantity
        enteredCostText = calculation.enteredCost.map(DecimalText.exact)
        enteredLossText = calculation.enteredLoss.map(DecimalText.exact)
        enteredGainText = calculation.enteredGain.map(DecimalText.exact)
        riskAsCapitalPercentageText = calculation.enteredRiskPercentOfCapital.map(DecimalText.exact)
        statusRaw = draft.status.rawValue
        notes = draft.notes
        updatedAt = .now
    }

    var displayName: String {
        !companyName.isEmpty ? companyName : (!symbol.isEmpty ? symbol : "未命名计划")
    }
}
