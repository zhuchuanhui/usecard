import SwiftData
import SwiftUI
import UseCardCore

/// Keeps the SwiftData view model and the cross-platform iCloud ledger in sync
/// even when the user opens the recommendation tab before the holdings tab.
struct SharedHoldingsBootstrap: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HoldingRecord.createdAt) private var holdings: [HoldingRecord]
    @State private var isSyncing = false
    private let store = SharedHoldingsStore()

    private var fingerprint: [String] {
        holdings.map { holding in
            [
                holding.cardID,
                holding.enrolledBenefitKeysJSON,
                holding.hasAnnualSpendEstimate ? "1" : "0",
                String(holding.annualSpendYen),
                String(holding.pointValueYen),
                holding.pendingName ?? "",
                holding.pendingIssuerID ?? "",
                holding.pendingIssuerName ?? "",
                holding.pendingOfficialURLString ?? ""
            ].joined(separator: "|")
        }
        .sorted()
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { syncFromSharedStore() }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                syncFromSharedStore()
            }
            .onChange(of: fingerprint) { _, _ in
                guard !isSyncing else { return }
                store.merge(holdings.map { $0.sharedRecord() })
            }
    }

    private func syncFromSharedStore() {
        guard !isSyncing else { return }
        isSyncing = true
        store.synchronize()

        let remoteRecords = Dictionary(
            uniqueKeysWithValues: store.records().map { ($0.cardID, $0) }
        )
        var localByID = Dictionary(uniqueKeysWithValues: holdings.map { ($0.cardID, $0) })

        for record in remoteRecords.values {
            if record.isDeleted {
                if let local = localByID.removeValue(forKey: record.cardID) {
                    modelContext.delete(local)
                }
                continue
            }

            if let local = localByID[record.cardID] {
                apply(record, to: local)
            } else {
                let local = HoldingRecord(sharedRecord: record)
                modelContext.insert(local)
                localByID[record.cardID] = local
            }
        }

        // Publish records entered locally before this device first saw the
        // shared ledger. Tombstones are deliberately not resurrected here.
        for local in localByID.values where remoteRecords[local.cardID] == nil {
            store.upsert(local.sharedRecord())
        }

        try? modelContext.save()
        isSyncing = false
    }

    private func apply(_ remote: SharedHoldingRecord, to local: HoldingRecord) {
        if let enrolledBenefitKeys = remote.enrolledBenefitKeys {
            local.enrolledBenefitKeys = enrolledBenefitKeys
        }
        if let annualSpendYen = remote.annualSpendYen {
            local.annualSpendYen = annualSpendYen
        }
        if let hasAnnualSpendEstimate = remote.hasAnnualSpendEstimate {
            local.hasAnnualSpendEstimate = hasAnnualSpendEstimate
        }
        if let pointValueYen = remote.pointValueYen {
            local.pointValueYen = pointValueYen
        }
        if let pendingName = remote.pendingName {
            local.pendingName = pendingName
        }
        if let pendingIssuerID = remote.pendingIssuerID {
            local.pendingIssuerID = pendingIssuerID
        }
        if let pendingIssuerName = remote.pendingIssuerName {
            local.pendingIssuerName = pendingIssuerName
        }
        if let pendingOfficialURLString = remote.pendingOfficialURLString {
            local.pendingOfficialURLString = pendingOfficialURLString
        }
    }
}
