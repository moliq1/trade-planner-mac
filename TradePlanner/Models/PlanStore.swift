import Foundation
import Combine

/// Local, offline storage compatible with macOS 13 (SwiftData requires macOS 14).
/// All mutations are persisted atomically before publishing the new in-memory snapshot.
final class PlanStore: ObservableObject {
    @Published private(set) var plans: [TradePlan] = []
    @Published private(set) var loadError: String?

    private let fileURL: URL
    private var backupURL: URL { fileURL.appendingPathExtension("backup") }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("TradePlanner", isDirectory: true)
        fileURL = base.appendingPathComponent("trade-plans.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            plans = try Self.read(fileURL)
        } catch {
            // Never silently reset a damaged trade history and overwrite it.
            // A previous valid snapshot is kept in .backup for manual recovery.
            loadError = "历史文件无法读取：\(error.localizedDescription)。原文件已保留；请先备份或修复数据。"
        }
    }

    @discardableResult
    func save(draft: TradeDraft, calculation: TradeCalculation, editingID: UUID?) throws -> UUID {
        try checkHealthy()
        var updated = plans
        let resultID: UUID
        if let editingID {
            guard let index = updated.firstIndex(where: { $0.id == editingID }) else {
                throw PlanStoreError.notFound
            }
            updated[index].apply(draft: draft, calculation: calculation)
            resultID = editingID
        } else {
            let newPlan = TradePlan(draft: draft, calculation: calculation)
            resultID = newPlan.id
            updated.append(newPlan)
        }
        try persist(updated)
        plans = updated.sorted { $0.updatedAt > $1.updatedAt }
        return resultID
    }

    func delete(id: UUID) throws {
        try checkHealthy()
        let updated = plans.filter { $0.id != id }
        guard updated.count != plans.count else { throw PlanStoreError.notFound }
        try persist(updated)
        plans = updated
    }

    private func checkHealthy() throws {
        if let loadError { throw PlanStoreError.unreadable(loadError) }
    }

    private static func read(_ url: URL) throws -> [TradePlan] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TradePlan].self, from: Data(contentsOf: url))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist(_ value: [TradePlan]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)

        let manager = FileManager.default
        try manager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if manager.fileExists(atPath: fileURL.path) {
            // Preserve one previous successfully encoded snapshot.
            // Do not replace the backup if a corrupted file is encountered.
            _ = try Self.read(fileURL)
            if manager.fileExists(atPath: backupURL.path) {
                try manager.removeItem(at: backupURL)
            }
            try manager.copyItem(at: fileURL, to: backupURL)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}

enum PlanStoreError: LocalizedError {
    case notFound
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "找不到该交易计划；它可能已被删除。"
        case .unreadable(let detail): return detail
        }
    }
}
