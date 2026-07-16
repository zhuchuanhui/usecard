import SwiftUI
import UseCardCore

struct CatalogView: View {
    let catalogStore: CatalogStore
    @State private var searchText = ""

    private var products: [CardProduct] {
        let all = catalogStore.catalog?.products ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.issuerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(products) { product in
            NavigationLink {
                ProductDetailView(product: product)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.headline)
                    Text(product.issuerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(product.annualFeeYen == 0 ? "年会費無料" : "年会費 \(product.annualFeeYen, format: .currency(code: "JPY"))")
                        Spacer()
                        if product.sources.contains(where: { $0.freshness != .fresh }) {
                            Label("要確認", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .searchable(text: $searchText, prompt: "カード名・発行会社")
        .navigationTitle("カード検索")
        .overlay {
            if products.isEmpty && catalogStore.catalog != nil {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct ProductDetailView: View {
    let product: CardProduct

    var body: some View {
        List {
            Section("基本情報") {
                LabeledContent("発行会社", value: product.issuerName)
                LabeledContent(
                    "年会費",
                    value: product.annualFeeYen == 0
                        ? "無料"
                        : product.annualFeeYen.formatted(.currency(code: "JPY"))
                )
                LabeledContent("国際ブランド", value: product.networks.map(\.displayName).joined(separator: " / "))
                Text(product.eligibilityNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("還元ルール") {
                ForEach(product.benefitRules) { rule in
                    Link(destination: rule.source.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.title)
                                .foregroundStyle(.primary)
                            Text(rule.reward.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("公式情報") {
                ForEach(product.sources, id: \.url) { source in
                    Link(destination: source.url) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.url.host() ?? source.url.absoluteString)
                                Text("確認: \(source.observedAt)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: source.freshness == .fresh ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(source.freshness == .fresh ? .green : .orange)
                        }
                    }
                }
            }

            Section {
                Link("申込ページを開く", destination: product.applicationURL)
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension CardNetwork {
    var displayName: String {
        switch self {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .jcb: "JCB"
        case .americanExpress: "American Express"
        case .dinersClub: "Diners Club"
        case .unionPay: "UnionPay"
        }
    }
}

private extension RewardFormula {
    var summary: String {
        switch kind {
        case .cashbackRate:
            "\(ratePercent ?? 0, format: .number)%還元"
        case .pointsPerUnit:
            "\(unitAmountYen ?? 0, format: .number)円ごとに\(pointsPerUnit ?? 0, format: .number)ポイント"
        case .fixedYen:
            "\(fixedYen ?? 0, format: .currency(code: "JPY"))相当"
        }
    }
}
