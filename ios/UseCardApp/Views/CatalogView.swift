import SwiftUI
import UseCardCore

struct CatalogView: View {
    @Environment(\.appLanguage) private var language
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


    private var onlineCandidates: [OnlineCardCandidate] {
        guard !searchText.isEmpty else { return [] }
        let verifiedURLs = Set((catalogStore.catalog?.products ?? []).map { $0.applicationURL.absoluteString })
        return catalogStore.onlineCandidates.filter { candidate in
            !verifiedURLs.contains(candidate.officialURL.absoluteString)
                && (candidate.name.localizedCaseInsensitiveContains(searchText)
                || candidate.issuerName.localizedCaseInsensitiveContains(searchText)
                || candidate.aliases.contains { $0.localizedCaseInsensitiveContains(searchText) })
        }
        .prefix(50)
        .map { $0 }
    }

    var body: some View {
        List {
            Section(language.text("catalog.includedCards")) {
                ForEach(products) { product in
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
                                Text(product.annualFeeYen == 0 ? language.text("catalog.noAnnualFee") : language.format("catalog.annualFeeFormat", product.annualFeeYen.formatted(.currency(code: "JPY"))))
                                Spacer()
                                if product.sources.contains(where: { $0.freshness != .fresh }) {
                                    Label(language.text("catalog.needsReview"), systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            if !onlineCandidates.isEmpty {
                Section(language.text("catalog.onlineCandidates")) {
                    ForEach(onlineCandidates) { candidate in
                        Link(destination: candidate.officialURL) {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(candidate.name, systemImage: "network")
                                    .foregroundStyle(.primary)
                                Text("\(candidate.issuerName)・\(language.text("catalog.officialPage"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: language.text("catalog.searchPrompt"))
        .navigationTitle(language.text("tab.catalog"))
        .overlay {
            if products.isEmpty && onlineCandidates.isEmpty && catalogStore.catalog != nil {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct ProductDetailView: View {
    @Environment(\.appLanguage) private var language
    let product: CardProduct

    var body: some View {
        List {
            Section(language.text("catalog.basicInfo")) {
                LabeledContent(language.text("catalog.issuer"), value: product.issuerName)
                LabeledContent(
                    language.text("catalog.annualFee"),
                    value: product.annualFeeYen == 0
                        ? language.text("catalog.free")
                        : product.annualFeeYen.formatted(.currency(code: "JPY"))
                )
                LabeledContent(language.text("catalog.network"), value: product.networks.map(\.displayName).joined(separator: " / "))
                Text(product.eligibilityNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(language.text("catalog.rewardRules")) {
                ForEach(product.benefitRules) { rule in
                    Link(destination: rule.source.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.title)
                                .foregroundStyle(.primary)
                            Text(rule.reward.summary(language: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(language.text("catalog.officialInformation")) {
                ForEach(product.sources, id: \.url) { source in
                    Link(destination: source.url) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.url.host() ?? source.url.absoluteString)
                                Text(language.format("catalog.checkedAtFormat", source.observedAt))
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
                Link(language.text("link.openApplication"), destination: product.applicationURL)
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
    func summary(language: AppLanguage) -> String {
        switch kind {
        case .cashbackRate:
            language.format("reward.cashbackFormat", (ratePercent ?? 0).formatted(.number))
        case .pointsPerUnit:
            language.format("reward.pointsFormat", (unitAmountYen ?? 0).formatted(.number), (pointsPerUnit ?? 0).formatted(.number))
        case .fixedYen:
            language.format("reward.fixedFormat", (fixedYen ?? 0).formatted(.currency(code: "JPY")))
        }
    }
}
