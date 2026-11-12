import Foundation
import XCTest
@testable import TradeCore

final class TradePlanPersistenceTests: XCTestCase {
    func testNewDefaults() {
        let draft = TradeDraft()
        XCTAssertEqual(draft.capitalText, "1500000")
        XCTAssertEqual(draft.riskText, "1")
        XCTAssertTrue(draft.enteredQuantityText.isEmpty)
        XCTAssertEqual(draft.hkdToCnyText, "0.85633")
    }

    func testOldJSONRecordsDecodeWithoutNewManualQuantityFields() throws {
        let originalDraft = TradeDraft()
        let calculation = try TradeCalculator.calculate(originalDraft.calculationInput())
        let originalPlan = TradePlan(draft: originalDraft, calculation: calculation)
        let json = try JSONEncoder().encode(originalPlan)
        guard var oldRecord = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            XCTFail("Could not build sample record"); return
        }
        for key in ["hkdToCnyText", "enteredQuantity", "enteredCostText", "enteredLossText",
                    "enteredGainText", "riskAsCapitalPercentageText"] {
            oldRecord.removeValue(forKey: key)
        }
        let oldData = try JSONSerialization.data(withJSONObject: oldRecord)
        let restored = try JSONDecoder().decode(TradePlan.self, from: oldData)
        XCTAssertNil(restored.hkdToCnyText)
        XCTAssertNil(restored.enteredQuantity)
        XCTAssertNil(restored.enteredLossText)
        XCTAssertNil(restored.riskAsCapitalPercentageText)
        XCTAssertEqual(restored.entryText, originalPlan.entryText)
        XCTAssertEqual(restored.stopPriceText, originalPlan.stopPriceText)
    }

    func testSavingAndReloadingManualQuantity() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TradePlanner-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        var draft = TradeDraft()
        draft.symbol = "600000"
        draft.entryText = "100"
        draft.enteredQuantityText = "2000"
        let calculation = try TradeCalculator.calculate(draft.calculationInput())

        let store = PlanStore(directory: temp)
        XCTAssertNil(store.loadError)
        let id = try store.save(draft: draft, calculation: calculation, editingID: nil)
        XCTAssertEqual(store.plans.count, 1)
        XCTAssertEqual(store.plans.first?.enteredQuantity, 2000)
        XCTAssertEqual(store.plans.first?.enteredLossText, "10000")

        let reloaded = PlanStore(directory: temp)
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.plans.first?.id, id)
        XCTAssertEqual(reloaded.plans.first?.enteredQuantity, 2000)
        XCTAssertEqual(reloaded.plans.first?.riskAsCapitalPercentageText != nil, true)

        draft.enteredQuantityText = "1000"
        let updatedCalculation = try TradeCalculator.calculate(draft.calculationInput())
        let updatedID = try reloaded.save(
            draft: draft, calculation: updatedCalculation, editingID: id
        )
        XCTAssertEqual(updatedID, id)
        XCTAssertEqual(reloaded.plans.first?.enteredLossText, "5000")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: temp.appendingPathComponent("trade-plans.json.backup").path
        ))
    }

    func testHKDReferenceRateIsSavedAndRestoredAsSnapshot() throws {
        var draft = TradeDraft()
        draft.market = .hongKong
        draft.currencyCode = "HKD"
        draft.hkdToCnyText = "0.85633"
        draft.enteredQuantityText = "100"
        let calculation = try TradeCalculator.calculate(draft.calculationInput())
        let plan = TradePlan(draft: draft, calculation: calculation)
        XCTAssertEqual(plan.hkdToCnyText, "0.85633")
        XCTAssertEqual(plan.settlementCurrency, "CNY")
        XCTAssertEqual(plan.enteredCostText, "8563.3")
        let roundtrip = try JSONDecoder().decode(TradePlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(roundtrip.hkdToCnyText, "0.85633")
        XCTAssertEqual(TradeDraft(from: roundtrip).hkdToCnyText, "0.85633")
    }

    func testLegacyHKDRecordMarksLegacyCurrency() throws {
        var draft = TradeDraft()
        draft.market = .hongKong
        draft.currencyCode = "HKD"
        let plan = TradePlan(draft: draft, calculation: try TradeCalculator.calculate(draft.calculationInput()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        json.removeValue(forKey: "hkdToCnyText")
        let legacy = try JSONDecoder().decode(TradePlan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.hkdToCnyText)
        XCTAssertEqual(legacy.settlementCurrency, "HKD（旧版）")
        // Loading a legacy plan for editing uses a new explicit reference rate.
        XCTAssertEqual(TradeDraft(from: legacy).hkdToCnyText, "0.85633")
    }

}
