import Foundation

public enum PriceInputMode: String, CaseIterable, Codable, Sendable {
    case percentage
    case price
}

public struct TradeCalculationInput: Sendable {
    public var entryPrice: Decimal
    public var stopInput: Decimal
    public var stopMode: PriceInputMode
    public var targetInput: Decimal
    public var targetMode: PriceInputMode
    public var accountCapital: Decimal?
    public var riskPercentage: Decimal?
    public var lotSize: Int

    public init(
        entryPrice: Decimal,
        stopInput: Decimal,
        stopMode: PriceInputMode,
        targetInput: Decimal,
        targetMode: PriceInputMode,
        accountCapital: Decimal? = nil,
        riskPercentage: Decimal? = nil,
        lotSize: Int = 1
    ) {
        self.entryPrice = entryPrice
        self.stopInput = stopInput
        self.stopMode = stopMode
        self.targetInput = targetInput
        self.targetMode = targetMode
        self.accountCapital = accountCapital
        self.riskPercentage = riskPercentage
        self.lotSize = lotSize
    }
}

public struct TradeCalculation: Sendable {
    public let entryPrice: Decimal
    public let stopPrice: Decimal
    public let targetPrice: Decimal
    public let stopLossPercentage: Decimal
    public let targetGainPercentage: Decimal
    public let rewardRiskRatio: Decimal
    public let breakEvenWinRate: Decimal
    public let riskPerShare: Decimal
    public let rewardPerShare: Decimal
    public let riskBudget: Decimal?
    public let suggestedQuantity: Int?
    public let estimatedCost: Decimal?
    public let plannedLoss: Decimal?
    public let plannedGain: Decimal?
}

public enum TradeCalculationError: String, Error, LocalizedError, Equatable, Sendable {
    case invalidEntry
    case invalidStop
    case invalidTarget
    case invalidCapital
    case invalidRiskPercentage
    case invalidLotSize
    case excessiveQuantity

    public var errorDescription: String? {
        switch self {
        case .invalidEntry: return "买入价必须大于 0。"
        case .invalidStop: return "止损价必须大于 0 且低于买入价；止损比例必须在 0%～100% 之间。"
        case .invalidTarget: return "止盈价必须高于买入价，或输入大于 0% 的目标盈利比例。"
        case .invalidCapital: return "账户资金必须大于 0；若不计算仓位，请同时清空账户资金与风险比例。"
        case .invalidRiskPercentage: return "单笔风险比例必须大于 0% 且不超过 100%。"
        case .invalidLotSize: return "每手股数必须是大于 0 的整数。"
        case .excessiveQuantity: return "计算出的股数过大，请检查参数。"
        }
    }
}

public enum TradeCalculator {
    /// Long-only, pre-fee / pre-slippage planning model.
    public static func calculate(_ input: TradeCalculationInput) throws -> TradeCalculation {
        let entry = input.entryPrice
        guard entry > 0 else { throw TradeCalculationError.invalidEntry }
        guard input.lotSize > 0 else { throw TradeCalculationError.invalidLotSize }

        let stop: Decimal
        switch input.stopMode {
        case .price:
            stop = input.stopInput
        case .percentage:
            guard input.stopInput > 0 && input.stopInput < 100 else {
                throw TradeCalculationError.invalidStop
            }
            stop = entry * (1 - input.stopInput / 100)
        }
        guard stop > 0 && stop < entry else { throw TradeCalculationError.invalidStop }

        let target: Decimal
        switch input.targetMode {
        case .price:
            target = input.targetInput
        case .percentage:
            guard input.targetInput > 0 else { throw TradeCalculationError.invalidTarget }
            target = entry * (1 + input.targetInput / 100)
        }
        guard target > entry else { throw TradeCalculationError.invalidTarget }

        let riskPerShare = entry - stop
        let rewardPerShare = target - entry
        let ratio = rewardPerShare / riskPerShare
        let stopPct = riskPerShare / entry * 100
        let targetPct = rewardPerShare / entry * 100
        let breakEven = riskPerShare / (riskPerShare + rewardPerShare) * 100

        var riskBudget: Decimal?
        var quantity: Int?
        var cost: Decimal?
        var loss: Decimal?
        var gain: Decimal?

        switch (input.accountCapital, input.riskPercentage) {
        case (nil, nil): break
        case (nil, _): throw TradeCalculationError.invalidCapital
        case (_, nil): throw TradeCalculationError.invalidRiskPercentage
        case (let capital?, let riskPercent?):
            guard capital > 0 else { throw TradeCalculationError.invalidCapital }
            guard riskPercent > 0 && riskPercent <= 100 else {
                throw TradeCalculationError.invalidRiskPercentage
            }
            let budget = capital * riskPercent / 100
            let maxByRisk = budget / riskPerShare
            let maxByCash = capital / entry
            let maxShares = min(maxByRisk, maxByCash)
            let lots = (NSDecimalNumber(decimal: maxShares / Decimal(input.lotSize)))
                .rounding(accordingToBehavior: NSDecimalNumberHandler(
                    roundingMode: .down,
                    scale: 0,
                    raiseOnExactness: false,
                    raiseOnOverflow: false,
                    raiseOnUnderflow: false,
                    raiseOnDivideByZero: false
                ))
            guard lots.compare(NSDecimalNumber(value: Int.max / input.lotSize)) != .orderedDescending else {
                throw TradeCalculationError.excessiveQuantity
            }
            let shares = lots.intValue * input.lotSize
            riskBudget = budget
            quantity = shares
            cost = Decimal(shares) * entry
            loss = Decimal(shares) * riskPerShare
            gain = Decimal(shares) * rewardPerShare
        }

        return TradeCalculation(
            entryPrice: entry,
            stopPrice: stop,
            targetPrice: target,
            stopLossPercentage: stopPct,
            targetGainPercentage: targetPct,
            rewardRiskRatio: ratio,
            breakEvenWinRate: breakEven,
            riskPerShare: riskPerShare,
            rewardPerShare: rewardPerShare,
            riskBudget: riskBudget,
            suggestedQuantity: quantity,
            estimatedCost: cost,
            plannedLoss: loss,
            plannedGain: gain
        )
    }
}

public enum DecimalText {
    public static func parse(_ string: String) -> Decimal? {
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty,
              normalized.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#,
                               options: .regularExpression) != nil else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Use for persistent numeric snapshots; never truncate to UI display precision.
    public static func exact(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    public static func display(_ value: Decimal, places: Int = 2) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US")
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = places
        return numberFormatter.string(from: NSDecimalNumber(decimal: value)) ?? exact(value)
    }
}
