import Foundation
import XCTest
@testable import TradeCore

final class TradeCalculatorTests: XCTestCase {
    func testPercentageModeAndRiskSizing() throws {
        let result = try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 5, stopMode: .percentage,
            targetInput: 15, targetMode: .percentage,
            accountCapital: 100_000, riskPercentage: 1, lotSize: 100
        ))
        XCTAssertEqual(result.stopPrice, 95)
        XCTAssertEqual(result.targetPrice, 115)
        XCTAssertEqual(result.rewardRiskRatio, 3)
        XCTAssertEqual(result.breakEvenWinRate, 25)
        XCTAssertEqual(result.suggestedQuantity, 200)
        XCTAssertEqual(result.estimatedCost, 20_000)
        XCTAssertEqual(result.plannedLoss, 1_000)
        XCTAssertEqual(result.plannedGain, 3_000)
    }

    func testPriceModeForHongKongStock() throws {
        let result = try TradeCalculator.calculate(.init(
            entryPrice: Decimal(string: "28.4")!,
            stopInput: 27, stopMode: .price,
            targetInput: Decimal(string: "38.5")!, targetMode: .price
        ))
        XCTAssertEqual(result.stopPrice, 27)
        XCTAssertEqual(result.targetPrice, Decimal(string: "38.5")!)
        XCTAssertEqual(result.suggestedQuantity, nil)
        XCTAssertGreaterThan(NSDecimalNumber(decimal: result.rewardRiskRatio).doubleValue, 7.21)
        XCTAssertLessThan(NSDecimalNumber(decimal: result.rewardRiskRatio).doubleValue, 7.22)
    }

    func testRiskLimitedByCash() throws {
        let result = try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 90, stopMode: .price,
            targetInput: 120, targetMode: .price,
            accountCapital: 1_000, riskPercentage: 100, lotSize: 1
        ))
        XCTAssertEqual(result.suggestedQuantity, 10)
        XCTAssertEqual(result.plannedLoss, 100)
    }

    func testRoundDownByLotSize() throws {
        let result = try TradeCalculator.calculate(.init(
            entryPrice: 20, stopInput: 19, stopMode: .price,
            targetInput: 24, targetMode: .price,
            accountCapital: 10_000, riskPercentage: 1, lotSize: 100
        ))
        XCTAssertEqual(result.suggestedQuantity, 100)
    }

    func testNoLotsAffordable() throws {
        let result = try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 95, stopMode: .price,
            targetInput: 115, targetMode: .price,
            accountCapital: 500, riskPercentage: 1, lotSize: 100
        ))
        XCTAssertEqual(result.suggestedQuantity, 0)
        XCTAssertEqual(result.plannedLoss, 0)
    }

    func testValidation() {
        XCTAssertThrowsError(try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 0, stopMode: .percentage,
            targetInput: 120, targetMode: .price
        ))) { XCTAssertEqual($0 as? TradeCalculationError, .invalidStop) }

        XCTAssertThrowsError(try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 95, stopMode: .price,
            targetInput: 100, targetMode: .price
        ))) { XCTAssertEqual($0 as? TradeCalculationError, .invalidTarget) }

        XCTAssertThrowsError(try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 95, stopMode: .price,
            targetInput: 115, targetMode: .price,
            accountCapital: 1000, riskPercentage: nil
        ))) { XCTAssertEqual($0 as? TradeCalculationError, .invalidRiskPercentage) }
    }

    func testDecimalParsingAndExactStorage() {
        XCTAssertEqual(DecimalText.parse("1,234.5678"), Decimal(string: "1234.5678"))
        XCTAssertNil(DecimalText.parse("   "))
        XCTAssertNil(DecimalText.parse("12abc"))
        XCTAssertNil(DecimalText.parse("1..2"))
        XCTAssertEqual(DecimalText.exact(Decimal(string: "28.4321")!), "28.4321")
    }

    func testManualQuantityProfitLossAndCapitalRisk() throws {
        let output = try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 95, stopMode: .price,
            targetInput: 115, targetMode: .price,
            accountCapital: 1_500_000, riskPercentage: 1,
            lotSize: 100, enteredQuantity: 2_000
        ))
        XCTAssertEqual(output.enteredQuantity, 2_000)
        XCTAssertEqual(output.enteredCost, 200_000)
        XCTAssertEqual(output.enteredLoss, 10_000)
        XCTAssertEqual(output.enteredGain, 30_000)
        XCTAssertEqual(NSDecimalNumber(decimal: output.enteredRiskPercentOfCapital ?? 0).doubleValue, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(output.exceedsRiskBudget, false)
        XCTAssertEqual(output.exceedsCapital, false)
        XCTAssertEqual(output.suggestedQuantity, 3_000) // separate from manual choice
    }

    func testManualQuantityOverRiskBudgetAndOverCapital() throws {
        let output = try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 90, stopMode: .price,
            targetInput: 120, targetMode: .price,
            accountCapital: 10_000, riskPercentage: 1, lotSize: 1,
            enteredQuantity: 200
        ))
        XCTAssertEqual(output.enteredLoss, 2_000)
        XCTAssertEqual(output.enteredGain, 4_000)
        XCTAssertEqual(output.enteredRiskPercentOfCapital, 20)
        XCTAssertEqual(output.exceedsRiskBudget, true)
        XCTAssertEqual(output.exceedsCapital, true)
    }

    func testNoEnteredQuantityKeepsRecommendationOnly() throws {
        let output = try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 95, stopMode: .price,
            targetInput: 115, targetMode: .price,
            accountCapital: 1_500_000, riskPercentage: 1
        ))
        XCTAssertNil(output.enteredLoss)
        XCTAssertNil(output.enteredGain)
        XCTAssertNil(output.enteredRiskPercentOfCapital)
        XCTAssertNotNil(output.suggestedQuantity)
    }

    func testRejectsInvalidManualQuantity() {
        XCTAssertThrowsError(try TradeCalculator.calculate(.init(
            entryPrice: 100, stopInput: 5, stopMode: .percentage,
            targetInput: 15, targetMode: .percentage,
            enteredQuantity: 0
        ))) { XCTAssertEqual($0 as? TradeCalculationError, .invalidEnteredQuantity) }
    }

}
