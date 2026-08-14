import Foundation

/// The small, account-level record shared by the iOS and macOS apps.
///
/// Card numbers and transactions are intentionally not included. The record
/// only describes which product is held and the optional local settings that
/// are safe to mirror between the user's own devices.
public struct SharedHoldingRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { cardID }

    public let cardID: String
    public let pendingIssuerID: String?
    public let pendingName: String?
    public let pendingIssuerName: String?
    public let pendingOfficialURLString: String?
    public let enrolledBenefitKeys: Set<String>?
    public let annualSpendYen: Double?
    public let hasAnnualSpendEstimate: Bool?
    public let pointValueYen: Double?
    public let createdAt: Date
    public let updatedAt: Date
    public let isDeleted: Bool

    public init(
        cardID: String,
        pendingIssuerID: String? = nil,
        pendingName: String? = nil,
        pendingIssuerName: String? = nil,
        pendingOfficialURLString: String? = nil,
        enrolledBenefitKeys: Set<String>? = nil,
        annualSpendYen: Double? = nil,
        hasAnnualSpendEstimate: Bool? = nil,
        pointValueYen: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.cardID = cardID
        self.pendingIssuerID = pendingIssuerID
        self.pendingName = pendingName
        self.pendingIssuerName = pendingIssuerName
        self.pendingOfficialURLString = pendingOfficialURLString
        self.enrolledBenefitKeys = enrolledBenefitKeys
        self.annualSpendYen = annualSpendYen
        self.hasAnnualSpendEstimate = hasAnnualSpendEstimate
        self.pointValueYen = pointValueYen
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    public static func tombstone(cardID: String, updatedAt: Date = Date()) -> Self {
        Self(cardID: cardID, updatedAt: updatedAt, isDeleted: true)
    }
}

/// A lightweight iCloud KVS bridge used by both app targets.
///
/// SwiftData/CloudKit remains the iOS database, while this bridge makes the
/// ownership list visible to the native macOS app too. Records are merged by
/// timestamp and deletions are retained as tombstones so a device coming back
/// online does not resurrect a card that was removed elsewhere.
public final class SharedHoldingsStore: @unchecked Sendable {
    public static let key = "jp.usecard.shared.holdings.v1"

    private struct Envelope: Codable {
        let schemaVersion: Int
        var records: [SharedHoldingRecord]
    }

    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }

    public func records() -> [SharedHoldingRecord] {
        guard let data = store.data(forKey: Self.key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1 else {
            return []
        }
        return envelope.records
    }

    public func activeRecords() -> [SharedHoldingRecord] {
        records().filter { !$0.isDeleted }
    }

    public func upsert(_ record: SharedHoldingRecord) {
        merge([record])
    }

    public func remove(cardID: String, updatedAt: Date = Date()) {
        merge([.tombstone(cardID: cardID, updatedAt: updatedAt)])
    }

    public func merge(_ incoming: [SharedHoldingRecord]) {
        guard !incoming.isEmpty else { return }
        var byCardID = Dictionary(uniqueKeysWithValues: records().map { ($0.cardID, $0) })
        for record in incoming {
            guard let existing = byCardID[record.cardID] else {
                byCardID[record.cardID] = record
                continue
            }
            if record.updatedAt >= existing.updatedAt {
                byCardID[record.cardID] = record
            }
        }

        let envelope = Envelope(
            schemaVersion: 1,
            records: byCardID.values.sorted { $0.cardID < $1.cardID }
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        store.set(data, forKey: Self.key)
        store.synchronize()
    }
}
