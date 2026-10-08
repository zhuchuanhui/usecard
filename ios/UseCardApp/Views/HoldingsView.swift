import SwiftData
import SwiftUI
import UseCardCore

struct HoldingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HoldingRecord.createdAt) private var holdings: [HoldingRecord]
    let catalogStore: CatalogStore
    @State private var isAdding = false
    private let sharedHoldingsStore = SharedHoldingsStore()

    var body: some View {
        List {
            if holdings.isEmpty {
                ContentUnavailableView(
                    language.text("holdings.empty"),
                    systemImage: "creditcard",
                    description: Text(language.text("holdings.emptyDescription"))
                )
            } else {
                ForEach(holdings) { holding in
                    if let card = catalogStore.catalog?.products.first(where: { $0.id == holding.cardID }) {
                        NavigationLink {
                            HoldingDetailView(holding: holding, card: card)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.name)
                                    .font(.headline)
                                Text(card.issuerName)
                                    .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else if let pendingName = holding.pendingName {
                        NavigationLink {
                            PendingHoldingDetailView(holding: holding)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pendingName)
                                    .font(.headline)
                                Text("\(holding.pendingIssuerName ?? language.text("holdings.issuerPending"))・\(language.text("holdings.pending"))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Label(language.format("holdings.missingCardFormat", holding.cardID), systemImage: "exclamationmark.triangle")
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(language.text("tab.holdings"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label(language.text("action.add"), systemImage: "plus")
                }
                .disabled(catalogStore.catalog == nil)
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                CardPickerView(
                    products: catalogStore.catalog?.products ?? [],
                    candidates: catalogStore.onlineCandidates,
                    excludedIDs: Set(holdings.map(\.cardID)),
                    excludedCandidateURLs: Set(holdings.compactMap(\.pendingOfficialURLString))
                ) { product in
                    let holding = HoldingRecord(cardID: product.id)
                    modelContext.insert(holding)
                    sharedHoldingsStore.upsert(holding.sharedRecord())
                    try? modelContext.save()
                    isAdding = false
                } onSelectCandidate: { candidate in
                    let holding = HoldingRecord(
                        cardID: "pending-\(UUID().uuidString.lowercased())",
                        pendingCandidate: candidate
                    )
                    modelContext.insert(holding)
                    sharedHoldingsStore.upsert(holding.sharedRecord())
                    try? modelContext.save()
                    isAdding = false
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let holding = holdings[index]
            sharedHoldingsStore.remove(cardID: holding.cardID)
            modelContext.delete(holding)
        }
        try? modelContext.save()
    }

}

private struct CardPickerView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let products: [CardProduct]
    let candidates: [OnlineCardCandidate]
    let excludedIDs: Set<String>
    let excludedCandidateURLs: Set<String>
    let onSelect: (CardProduct) -> Void
    let onSelectCandidate: (OnlineCardCandidate) -> Void
    @State private var searchText = ""

    private var filteredProducts: [CardProduct] {
        products.filter { product in
            !excludedIDs.contains(product.id)
                && (searchText.isEmpty
                    || product.name.localizedCaseInsensitiveContains(searchText)
                    || product.issuerName.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var filteredCandidates: [OnlineCardCandidate] {
        guard !searchText.isEmpty else { return [] }
        let verifiedURLs = Set(products.map { $0.applicationURL.absoluteString })
        return candidates.filter { candidate in
            !excludedCandidateURLs.contains(candidate.officialURL.absoluteString)
                && !verifiedURLs.contains(candidate.officialURL.absoluteString)
                && (searchText.isEmpty
                    || candidate.name.localizedCaseInsensitiveContains(searchText)
                    || candidate.issuerName.localizedCaseInsensitiveContains(searchText)
                    || candidate.aliases.contains { $0.localizedCaseInsensitiveContains(searchText) })
        }
        .prefix(50)
        .map { $0 }
    }

    var body: some View {
        List {
            Section(language.text("catalog.includedCards")) {
                ForEach(filteredProducts) { product in
                    Button {
                        onSelect(product)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.name)
                                .foregroundStyle(.primary)
                            Text(product.issuerName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !filteredCandidates.isEmpty {
                Section(language.text("catalog.onlineCandidates")) {
                    ForEach(filteredCandidates) { candidate in
                        Button {
                            onSelectCandidate(candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(candidate.name, systemImage: "network")
                                    .foregroundStyle(.primary)
                                Text("\(candidate.issuerName)・\(language.text("holdings.addPendingDescription"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: language.text("catalog.searchPrompt"))
        .navigationTitle(language.text("holdings.addCard"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.text("action.close")) { dismiss() }
            }
        }
    }
}

private struct HoldingDetailView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var holding: HoldingRecord
    let card: CardProduct

    private var enrollmentOptions: [(key: String, label: String)] {
        switch card.id {
        case "paypay-card":
            [("paypay-linked-and-verified", language.text("benefit.paypayVerified"))]
        default:
            []
        }
    }

    var body: some View {
        Form {
            Section(language.text("holdings.usage")) {
                Toggle(language.text("holdings.enterAnnualSpend"), isOn: $holding.hasAnnualSpendEstimate)
                if holding.hasAnnualSpendEstimate {
                    TextField(
                        language.text("holdings.annualSpend"),
                        value: $holding.annualSpendYen,
                        format: .currency(code: "JPY")
                    )
                    .keyboardType(.numberPad)
                }
                TextField(
                    language.text("holdings.pointValue"),
                    value: $holding.pointValueYen,
                    format: .currency(code: "JPY")
                )
                .keyboardType(.decimalPad)
            }

            if !enrollmentOptions.isEmpty {
                Section(language.text("holdings.enrolledBenefits")) {
                    ForEach(enrollmentOptions, id: \.key) { option in
                        Toggle(
                            option.label,
                            isOn: Binding(
                                get: { holding.enrolledBenefitKeys.contains(option.key) },
                                set: { isOn in
                                    var values = holding.enrolledBenefitKeys
                                    if isOn { values.insert(option.key) } else { values.remove(option.key) }
                                    holding.enrolledBenefitKeys = values
                                }
                            )
                        )
                    }
                }
            }

            Section {
                Link(language.text("link.openOfficialSite"), destination: card.applicationURL)
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PendingHoldingDetailView: View {
    @Environment(\.appLanguage) private var language
    let holding: HoldingRecord

    var body: some View {
        List {
            Section(language.text("holdings.card")) {
                LabeledContent(language.text("catalog.cardName"), value: holding.pendingName ?? language.text("common.unknown"))
                LabeledContent(language.text("catalog.issuer"), value: holding.pendingIssuerName ?? language.text("common.checking"))
                Label(language.text("holdings.verificationInProgress"), systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            if let url = holding.pendingOfficialURL {
                Section {
                    Link(language.text("link.openOfficialPage"), destination: url)
                }
            }
        }
        .navigationTitle(holding.pendingName ?? language.text("holdings.pendingCard"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
