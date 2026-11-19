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


    func testClosingAndReopeningPersistenceWithHKD() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TradePlanner-Close-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PlanStore(directory: temp)
        var draft = TradeDraft()
        draft.market = .hongKong
        draft.currencyCode = "HKD"
        draft.entryText = "102"
        draft.stopMode = .price
        draft.stopText = "94"
        draft.targetMode = .price
        draft.targetText = "114"
        draft.enteredQuantityText = "400"
        draft.status = .entered
        let plan = try TradeCalculator.calculate(draft.calculationInput())
        let id = try store.save(draft: draft, calculation: plan, editingID: nil)
        XCTAssertNil(store.plans.first?.sellPriceText)

        draft.status = .closed
        draft.sellPriceText = "100"
        _ = try store.save(draft: draft, calculation: plan, editingID: id)
        XCTAssertEqual(store.plans.first?.sellPriceText, "100")
        XCTAssertEqual(store.plans.first?.realizedPnLText, "-685.064")
        XCTAssertEqual(store.plans.first?.realizedRText, "-0.25")
        XCTAssertNotNil(store.plans.first?.closedAt)

        let reloaded = PlanStore(directory: temp)
        XCTAssertEqual(reloaded.plans.first?.statusRaw, PlanStatus.closed.rawValue)
        XCTAssertEqual(reloaded.plans.first?.sellPriceText, "100")
        XCTAssertEqual(TradeDraft(from: try XCTUnwrap(reloaded.plans.first)).sellPriceText, "100")

        draft.status = .entered
        _ = try reloaded.save(draft: draft, calculation: plan, editingID: id)
        XCTAssertNil(reloaded.plans.first?.sellPriceText)
        XCTAssertNil(reloaded.plans.first?.closedAt)
    }

    func testCloseValidationDoesNotAlterExistingRecord() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TradePlanner-Validation-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PlanStore(directory: temp)
        var draft = TradeDraft()
        draft.symbol = "601899"
        draft.enteredQuantityText = "100"
        let plan = try TradeCalculator.calculate(draft.calculationInput())
        let id = try store.save(draft: draft, calculation: plan, editingID: nil)

        draft.status = .closed
        XCTAssertThrowsError(try store.save(draft: draft, calculation: plan, editingID: id)) {
            XCTAssertEqual($0 as? TradeCalculationError, .missingSellPrice)
        }
        draft.sellPriceText = "120"
        draft.enteredQuantityText = ""
        XCTAssertThrowsError(try store.save(
            draft: draft, calculation: try TradeCalculator.calculate(draft.calculationInput()),
            editingID: id
        )) {
            XCTAssertEqual($0 as? TradeCalculationError, .missingCloseQuantity)
        }
        XCTAssertEqual(store.plans.first?.statusRaw, PlanStatus.planned.rawValue)
    }

    func testHistoricalRecordsWithoutExitFieldsDecode() throws {
        let draft = TradeDraft()
        let plan = TradePlan(draft: draft, calculation: try TradeCalculator.calculate(draft.calculationInput()))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        for key in ["sellPriceText", "sellProceedsText", "realizedPnLText",
                    "realizedReturnPctText", "realizedRText", "closedAt"] {
            raw.removeValue(forKey: key)
        }
        let old = try JSONDecoder().decode(TradePlan.self,
            from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(old.sellPriceText)
        XCTAssertNil(old.realizedPnLText)
        XCTAssertNil(old.closedAt)
    }


    func testBuyDateDefaultsToCreationDayAndCanBeEdited() throws {
        let draft = TradeDraft()
        XCTAssertTrue(Calendar.current.isDate(draft.buyDate, inSameDayAs: Date()))

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TradePlanner-Date-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PlanStore(directory: temp)
        var edited = draft
        edited.symbol = "601899"
        let oldDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))!
        edited.buyDate = oldDate
        let input = try TradeCalculator.calculate(edited.calculationInput())
        let id = try store.save(draft: edited, calculation: input, editingID: nil)
        XCTAssertEqual(store.plans.first?.buyDate, oldDate)

        let loaded = PlanStore(directory: temp)
        let plan = try XCTUnwrap(loaded.plans.first)
        XCTAssertEqual(plan.buyDate, oldDate)
        XCTAssertEqual(TradeDraft(from: plan).buyDate, oldDate)

        edited.buyDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
        _ = try loaded.save(draft: edited, calculation: input, editingID: id)
        XCTAssertEqual(loaded.plans.first?.buyDate, edited.buyDate)
    }

    func testOldRecordsUseCreatedAtForSortButAreNotMarkedAsActualBuyDate() throws {
        let draft = TradeDraft()
        let plan = TradePlan(draft: draft, calculation: try TradeCalculator.calculate(draft.calculationInput()))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        raw.removeValue(forKey: "buyDate")
        raw.removeValue(forKey: "reviewNotes")
        let legacy = try JSONDecoder().decode(
            TradePlan.self, from: JSONSerialization.data(withJSONObject: raw)
        )
        XCTAssertNil(legacy.buyDate)
        XCTAssertNil(legacy.reviewNotes)
        XCTAssertEqual(legacy.effectiveBuyDate, legacy.createdAt)
        XCTAssertEqual(TradeDraft(from: legacy).buyDate, legacy.createdAt)
    }

    func testClosedPlanReviewSurvivesSaveReloadAndEditing() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TradePlanner-Review-\(UUID().uuidString)", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PlanStore(directory: temp)
        var draft = TradeDraft()
        draft.symbol = "02899"
        draft.enteredQuantityText = "200"
        draft.status = .closed
        draft.sellPriceText = "110"
        draft.reviewNotes = "按计划止盈；下次注意量能。"
        let calculation = try TradeCalculator.calculate(draft.calculationInput())
        let id = try store.save(draft: draft, calculation: calculation, editingID: nil)
        XCTAssertEqual(store.plans.first?.reviewNotes, draft.reviewNotes)

        let reloaded = PlanStore(directory: temp)
        let restored = try XCTUnwrap(reloaded.plans.first)
        XCTAssertEqual(restored.reviewNotes, draft.reviewNotes)
        var edit = TradeDraft(from: restored)
        edit.reviewNotes += " 未出现冲动追涨。"
        _ = try reloaded.save(draft: edit, calculation: calculation, editingID: id)
        XCTAssertEqual(reloaded.plans.first?.reviewNotes, edit.reviewNotes)
    }

    func testDateSortingWithinSameStatus() throws {
        var recent = TradeDraft()
        recent.status = .entered
        let old = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        let latest = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
        recent.buyDate = latest
        let newPlan = TradePlan(draft: recent, calculation: try TradeCalculator.calculate(recent.calculationInput()))
        recent.buyDate = old
        let oldPlan = TradePlan(draft: recent, calculation: try TradeCalculator.calculate(recent.calculationInput()))
        let sorted = [oldPlan, newPlan].sorted { $0.effectiveBuyDate > $1.effectiveBuyDate }
        XCTAssertEqual(sorted.map(\.buyDate), [latest, old])
    }

}
