import SwiftData
import SwiftUI
import UseCardCore

struct HoldingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HoldingRecord.createdAt) private var holdings: [HoldingRecord]
    let catalogStore: CatalogStore
    @State private var isAdding = false

    var body: some View {
        List {
            if holdings.isEmpty {
                ContentUnavailableView(
                    "カードがありません",
                    systemImage: "creditcard",
                    description: Text("右上の＋から手持ちカードを追加してください。")
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
                    } else {
                        Label("カタログにないカード（\(holding.cardID)）", systemImage: "exclamationmark.triangle")
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("手持ちカード")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .disabled(catalogStore.catalog == nil)
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                CardPickerView(
                    products: catalogStore.catalog?.products ?? [],
                    excludedIDs: Set(holdings.map(\.cardID))
                ) { product in
                    modelContext.insert(HoldingRecord(cardID: product.id))
                    try? modelContext.save()
                    isAdding = false
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(holdings[index])
        }
        try? modelContext.save()
    }
}

private struct CardPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let products: [CardProduct]
    let excludedIDs: Set<String>
    let onSelect: (CardProduct) -> Void
    @State private var searchText = ""

    private var filteredProducts: [CardProduct] {
        products.filter { product in
            !excludedIDs.contains(product.id)
                && (searchText.isEmpty
                    || product.name.localizedCaseInsensitiveContains(searchText)
                    || product.issuerName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List(filteredProducts) { product in
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
        .searchable(text: $searchText, prompt: "カード名・発行会社")
        .navigationTitle("カードを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
    }
}

private struct HoldingDetailView: View {
    @Bindable var holding: HoldingRecord
    let card: CardProduct

    private var enrollmentOptions: [(key: String, label: String)] {
        switch card.id {
        case "paypay-card":
            [("paypay-linked-and-verified", "PayPay連携・本人確認済み")]
        default:
            []
        }
    }

    var body: some View {
        Form {
            Section("利用状況") {
                Toggle("年間利用額を入力する", isOn: $holding.hasAnnualSpendEstimate)
                if holding.hasAnnualSpendEstimate {
                    TextField(
                        "年間利用額",
                        value: $holding.annualSpendYen,
                        format: .currency(code: "JPY")
                    )
                    .keyboardType(.numberPad)
                }
                TextField(
                    "1ポイントの価値",
                    value: $holding.pointValueYen,
                    format: .currency(code: "JPY")
                )
                .keyboardType(.decimalPad)
            }

            if !enrollmentOptions.isEmpty {
                Section("登録済み特典") {
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
                Link("公式サイトを開く", destination: card.applicationURL)
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
