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
    /// Published PBOC/CFETS central parity for 2026-11-12: CNY 85.633 per 100 HKD.
    static let defaultHKDToCNY = "0.85633"
    static let referenceRateDate = "2026-11-12"
    var symbol = ""
    var companyName = ""
    var market: TradeMarket = .chinaA
    var currencyCode = "CNY"
    var hkdToCnyText = TradeDraft.defaultHKDToCNY
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
    var sellPriceText = ""
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
        let fx: Decimal
        if market == .hongKong {
            guard let rate = DecimalText.parse(hkdToCnyText), rate > 0 else {
                throw TradeCalculationError.invalidExchangeRate
            }
            fx = rate
        } else {
            fx = 1
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
            enteredQuantity: enteredQuantity,
            priceToCNYRate: fx
        )
    }

    /// A closed plan must have actual sale price and a real planned share count.
    /// Non-closed records are not forced to supply execution data.
    func exitCalculation(using plan: TradeCalculation) throws -> TradeExitCalculation? {
        guard status == .closed else { return nil }
        guard !sellPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TradeCalculationError.missingSellPrice
        }
        guard let price = DecimalText.parse(sellPriceText), price > 0 else {
            throw TradeCalculationError.invalidSellPrice
        }
        return try TradeCalculator.calculateExit(plan: plan, sellPrice: price)
    }

    init() {}

    init(from plan: TradePlan) {
        symbol = plan.symbol
        companyName = plan.companyName
        market = TradeMarket(rawValue: plan.marketRaw) ?? .other
        currencyCode = plan.currencyCode
        hkdToCnyText = plan.hkdToCnyText ?? TradeDraft.defaultHKDToCNY
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
        sellPriceText = plan.sellPriceText ?? ""
        notes = plan.notes
    }
}

struct TradePlan: Identifiable, Codable {
    var id: UUID
    var symbol: String
    var companyName: String
    var marketRaw: String
    var currencyCode: String
    /// Optional to preserve decoding of older JSON records. Nil HKD = legacy unconverted amounts.
    var hkdToCnyText: String?

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

    // Optional fields allow decoding plans saved before real exit tracking existed.
    var sellPriceText: String?
    var sellProceedsText: String?
    var realizedPnLText: String?
    var realizedReturnPctText: String?
    var realizedRText: String?
    var closedAt: Date?

    var statusRaw: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(draft: TradeDraft, calculation: TradeCalculation, exit: TradeExitCalculation? = nil) {
        id = UUID()
        symbol = ""
        companyName = ""
        marketRaw = ""
        currencyCode = ""
        hkdToCnyText = nil
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
        sellPriceText = nil
        sellProceedsText = nil
        realizedPnLText = nil
        realizedReturnPctText = nil
        realizedRText = nil
        closedAt = nil
        statusRaw = ""
        notes = ""
        createdAt = .now
        updatedAt = .now
        apply(draft: draft, calculation: calculation, exit: exit)
    }

    mutating func apply(draft: TradeDraft, calculation: TradeCalculation, exit: TradeExitCalculation? = nil) {
        symbol = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        companyName = draft.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        marketRaw = draft.market.rawValue
        currencyCode = draft.currencyCode
        hkdToCnyText = draft.market == .hongKong ? DecimalText.exact(calculation.priceToCNYRate) : nil
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
        if draft.status == .closed, let exit = exit {
            sellPriceText = DecimalText.exact(exit.sellPrice)
            sellProceedsText = DecimalText.exact(exit.sellProceedsCNY)
            realizedPnLText = DecimalText.exact(exit.realizedPnLCNY)
            realizedReturnPctText = DecimalText.exact(exit.realizedReturnPercentage)
            realizedRText = DecimalText.exact(exit.realizedR)
            if closedAt == nil { closedAt = .now }
        } else {
            // A plan re-opened from closed no longer claims a realized exit.
            sellPriceText = nil
            sellProceedsText = nil
            realizedPnLText = nil
            realizedReturnPctText = nil
            realizedRText = nil
            closedAt = nil
        }
        notes = draft.notes
        updatedAt = .now
    }

    var settlementCurrency: String {
        if marketRaw == TradeMarket.hongKong.rawValue {
            return hkdToCnyText == nil ? "HKD（旧版）" : "CNY"
        }
        return marketRaw == TradeMarket.chinaA.rawValue ? "CNY" : currencyCode
    }

    var displayName: String {
        !companyName.isEmpty ? companyName : (!symbol.isEmpty ? symbol : "未命名计划")
    }
}
