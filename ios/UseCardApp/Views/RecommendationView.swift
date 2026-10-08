import SwiftData
import SwiftUI
import UseCardCore

struct RecommendationView: View {
    @Environment(\.appLanguage) private var language
    @Query(sort: \HoldingRecord.createdAt) private var holdingRecords: [HoldingRecord]
    let catalogStore: CatalogStore

    @State private var amountYen = 10_000.0
    @State private var merchantID = "general"
    @State private var categoryID = "general"
    @State private var channel = PurchaseChannel.inStore
    @State private var frequency = SpendFrequency.once
    @State private var purchaseDate = Date()
    @State private var detailedResult: CardRouteRankings?
    @State private var alternativeRecommendations: [AlternativePaymentRecommendation] = []
    @State private var isDetailedExpanded = false

    private let calculator = RecommendationCalculator()

    private var holdingIDs: [String] {
        holdingRecords.map(\.cardID)
    }

    private var automaticPlaces: [AutomaticPlace] {
        [
            AutomaticPlace(id: "aeon-group", categoryID: "groceries", channel: .inStore),
            AutomaticPlace(id: "seven-eleven", categoryID: "general", channel: .inStore),
            AutomaticPlace(id: "amazon", categoryID: "online-shopping", channel: .online),
            AutomaticPlace(id: "rakuten-market", categoryID: "online-shopping", channel: .online),
            AutomaticPlace(id: "jr-east-rail", categoryID: "transport", channel: .inStore)
        ]
    }

    private var automaticRecommendations: [AutomaticPlaceRecommendation] {
        guard let catalog = catalogStore.catalog else { return [] }
        let holdings = userHoldings(from: holdingRecords, catalog: catalog)
        return automaticPlaces.map { place in
            let intent = PurchaseIntent(
                amountYen: 10_000,
                merchantID: place.id,
                categoryID: place.categoryID,
                paymentMethod: .physical,
                channel: place.channel,
                frequency: .once,
                purchaseDate: Self.dateFormatter.string(from: Date())
            )
            let routes = calculator.bestCardRoutes(
                catalog: catalog,
                intent: intent,
                holdings: holdings,
                paymentMethods: paymentMethods(for: place.channel)
            )
            let alternatives = calculator.alternativePayments(
                catalog: catalogStore.alternativePaymentCatalog,
                intent: intent
            )
            let selectedCard = routes.bundle.owned.first ?? routes.bundle.available.first
            return AutomaticPlaceRecommendation(
                place: place,
                card: selectedCard,
                paymentMethod: selectedCard.flatMap { routes.paymentMethodByCardID[$0.card.id] },
                alternative: alternatives.first
            )
        }
    }

    var body: some View {
        Form {
            if let warning = catalogStore.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Section {
                if catalogStore.catalog == nil {
                    ProgressView(language.text("recommendation.loading"))
                } else {
                    Text(language.text("recommendation.intro"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(automaticRecommendations) { recommendation in
                        AutomaticPlaceRow(recommendation: recommendation)
                    }
                }
            } header: {
                Text(language.text("recommendation.usual"))
            } footer: {
                Text(language.text("recommendation.footer"))
            }

            Section {
                DisclosureGroup(language.text("recommendation.detailPrompt"), isExpanded: $isDetailedExpanded) {
                    TextField(language.text("field.amount"), value: $amountYen, format: .currency(code: "JPY"))
                        .keyboardType(.numberPad)

                    Picker(language.text("field.merchant"), selection: $merchantID) {
                        Text(language.text("merchant.none")).tag("general")
                        Text(language.text("place.aeon-group")).tag("aeon-group")
                        Text(language.text("place.seven-eleven")).tag("seven-eleven")
                        Text(language.text("place.lawson")).tag("lawson")
                        Text(language.text("place.mcdonalds")).tag("mcdonalds")
                        Text(language.text("place.mos-burger")).tag("mos-burger")
                        Text(language.text("place.kfc")).tag("kfc")
                        Text(language.text("place.yoshinoya")).tag("yoshinoya")
                        Text(language.text("place.saizeriya")).tag("saizeriya")
                        Text(language.text("place.gusto")).tag("gusto")
                        Text(language.text("place.sukiya")).tag("sukiya")
                        Text(language.text("place.hamazushi")).tag("hamazushi")
                        Text(language.text("place.doutor")).tag("doutor")
                        Text("Amazon").tag("amazon")
                        Text(language.text("place.rakuten-market")).tag("rakuten-market")
                    }

                    Picker(language.text("field.category"), selection: $categoryID) {
                        Text(language.text("category.general")).tag("general")
                        Text(language.text("category.groceries")).tag("groceries")
                        Text(language.text("category.dining")).tag("dining")
                        Text(language.text("category.travel")).tag("travel")
                        Text(language.text("category.transport")).tag("transport")
                        Text(language.text("category.utilities")).tag("utilities")
                        Text(language.text("category.online")).tag("online-shopping")
                    }

                    Picker(language.text("field.channel"), selection: $channel) {
                        Text(language.text("channel.inStore")).tag(PurchaseChannel.inStore)
                        Text(language.text("channel.online")).tag(PurchaseChannel.online)
                    }
                    .pickerStyle(.segmented)

                    Picker(language.text("field.frequency"), selection: $frequency) {
                        Text(language.text("frequency.once")).tag(SpendFrequency.once)
                        Text(language.text("frequency.monthly")).tag(SpendFrequency.monthly)
                        Text(language.text("frequency.quarterly")).tag(SpendFrequency.quarterly)
                        Text(language.text("frequency.annually")).tag(SpendFrequency.annually)
                    }

                    DatePicker(language.text("field.purchaseDate"), selection: $purchaseDate, displayedComponents: .date)

                    Button {
                        calculate()
                    } label: {
                        Label(language.text("recommendation.calculate"), systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(catalogStore.catalog == nil || amountYen <= 0)
                }
            } header: {
                Text(language.text("recommendation.detailHeader"))
            }

            if let detailedResult {
                RecommendationSection(
                    title: language.text("recommendation.ownedSection"),
                    emptyMessage: language.text("recommendation.noOwned"),
                    items: detailedResult.bundle.owned,
                    paymentMethodByCardID: detailedResult.paymentMethodByCardID
                )
                RecommendationSection(
                    title: language.text("recommendation.availableSection"),
                    emptyMessage: language.text("recommendation.noAvailable"),
                    items: detailedResult.bundle.available,
                    paymentMethodByCardID: detailedResult.paymentMethodByCardID
                )
                AlternativePaymentSection(recommendations: alternativeRecommendations)
            }
        }
        .navigationTitle(language.text("tab.recommendations"))
        .onChange(of: holdingIDs) { _, _ in
            if detailedResult != nil { calculate() }
        }
        .onChange(of: catalogStore.catalog?.version) { _, _ in
            if detailedResult != nil { calculate() }
        }
    }

    private func calculate() {
        guard let catalog = catalogStore.catalog else { return }
        let holdings = userHoldings(from: holdingRecords, catalog: catalog)
        let intent = PurchaseIntent(
            amountYen: amountYen,
            merchantID: merchantID == "general" ? nil : merchantID,
            categoryID: categoryID,
            paymentMethod: .physical,
            channel: channel,
            frequency: frequency,
            purchaseDate: Self.dateFormatter.string(from: purchaseDate)
        )
        detailedResult = calculator.bestCardRoutes(
            catalog: catalog,
            intent: intent,
            holdings: holdings,
            paymentMethods: paymentMethods(for: channel)
        )
        alternativeRecommendations = calculator.alternativePayments(
            catalog: catalogStore.alternativePaymentCatalog,
            intent: intent
        )
    }

    private func userHoldings(from records: [HoldingRecord], catalog: CardCatalog) -> [UserHolding] {
        records.map { record in
            let programID = catalog.products.first(where: { $0.id == record.cardID })?.pointProgramID
            return record.domainHolding(pointProgramID: programID)
        }
    }

    private func paymentMethods(for channel: PurchaseChannel) -> [PaymentMethod] {
        switch channel {
        case .inStore:
            [.physical, .contactless, .mobileContactless, .applePay, .mobileOrder, .qr]
        case .online:
            [.online, .applePay]
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct AutomaticPlace: Identifiable {
    let id: String
    let categoryID: String
    let channel: PurchaseChannel
}

private struct AutomaticPlaceRecommendation: Identifiable {
    let place: AutomaticPlace
    let card: CardRecommendation?
    let paymentMethod: PaymentMethod?
    let alternative: AlternativePaymentRecommendation?

    var id: String { place.id }
}

private struct AutomaticPlaceRow: View {
    @Environment(\.appLanguage) private var language
    let recommendation: AutomaticPlaceRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(language.text("place.\(recommendation.place.id)"))
                    .font(.headline)
                Spacer()
                Text(language.text("recommendation.basis"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let card = recommendation.card {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: card.isOwned ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(card.isOwned ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.card.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(language.text(card.isOwned ? "recommendation.owned" : "recommendation.candidate"))・\(paymentMethodLabel(recommendation.paymentMethod))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(card.immediateValueYen, format: .currency(code: "JPY"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                }
            } else {
                Text(language.text("recommendation.noCardData"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let alternative = recommendation.alternative {
                Text("\(language.text("recommendation.otherPayment")): \(alternative.product.paymentLabel)・\(language.text("recommendation.about"))\(yen(alternative.immediateValueYen))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func paymentMethodLabel(_ method: PaymentMethod?) -> String {
        switch method {
        case .physical: language.text("payment.physical")
        case .contactless: language.text("payment.contactless")
        case .mobileContactless: language.text("payment.mobileContactless")
        case .applePay: "Apple Pay"
        case .mobileOrder: language.text("payment.mobileOrder")
        case .qr: language.text("payment.qr")
        case .online: language.text("payment.online")
        case .recurring: language.text("payment.recurring")
        case nil: language.text("payment.unknown")
        }
    }

    private func yen(_ value: Double) -> String {
        value.formatted(.currency(code: "JPY"))
    }
}

private struct RecommendationSection: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let emptyMessage: String
    let items: [CardRecommendation]
    let paymentMethodByCardID: [String: PaymentMethod]

    var body: some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        RecommendationDetailView(
                            recommendation: item,
                            paymentMethod: paymentMethodByCardID[item.card.id]
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(index == 0 ? .white : .secondary)
                                .frame(width: 30, height: 30)
                                .background(index == 0 ? Color.accentColor : Color.secondary.opacity(0.12))
                                .clipShape(.circle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.card.name)
                                    .font(.headline)
                                Text(language.format("recommendation.resultFormat", item.immediateValueYen.formatted(.currency(code: "JPY")), item.effectiveReturnPercent.formatted(.number.precision(.fractionLength(1)))) )
                                    .font(.subheadline)
                                if let method = paymentMethodByCardID[item.card.id] {
                                    Text(paymentMethodLabel(method))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if item.possibleImmediateValueYen > item.immediateValueYen {
                                    Text(language.format("recommendation.maximumFormat", item.possibleImmediateValueYen.formatted(.currency(code: "JPY"))))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func paymentMethodLabel(_ method: PaymentMethod) -> String {
        switch method {
        case .physical: language.text("payment.physical")
        case .contactless: language.text("payment.contactless")
        case .mobileContactless: language.text("payment.mobileContactless")
        case .applePay: "Apple Pay"
        case .mobileOrder: language.text("payment.mobileOrder")
        case .qr: language.text("payment.qr")
        case .online: language.text("payment.online")
        case .recurring: language.text("payment.recurring")
        }
    }
}

private struct AlternativePaymentSection: View {
    @Environment(\.appLanguage) private var language
    let recommendations: [AlternativePaymentRecommendation]

    var body: some View {
        Section {
            if recommendations.isEmpty {
                Text(language.text("recommendation.noAlternative"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(recommendations.prefix(10))) { recommendation in
                    if let source = recommendation.product.sources.first {
                        Link(destination: source.url) {
                            recommendationRow(recommendation)
                        }
                    } else {
                        recommendationRow(recommendation)
                    }
                }
            }
        } header: {
            Text(language.text("recommendation.alternativeHeader"))
        } footer: {
            Text(language.text("recommendation.alternativeFooter"))
        }
    }

    private func recommendationRow(_ recommendation: AlternativePaymentRecommendation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.product.name)
                    .font(.headline)
                Text(language.text("payment.\(recommendation.product.id)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(recommendation.product.eligibilityNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(recommendation.immediateValueYen, format: .currency(code: "JPY"))
                    .font(.subheadline.weight(.bold))
                Text("\(recommendation.effectiveReturnPercent.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecommendationDetailView: View {
    @Environment(\.appLanguage) private var language
    let recommendation: CardRecommendation
    let paymentMethod: PaymentMethod?

    var body: some View {
        List {
            Section(language.text("recommendation.result")) {
                LabeledContent(language.text("recommendation.immediateValue"), value: recommendation.immediateValueYen, format: .currency(code: "JPY"))
                LabeledContent(language.text("recommendation.effectiveRate"), value: recommendation.effectiveReturnPercent, format: .percent.scale(1).precision(.fractionLength(1)))
                LabeledContent(language.text("recommendation.annualValue"), value: recommendation.annualNetValueYen, format: .currency(code: "JPY"))
                if let paymentMethod {
                    LabeledContent(language.text("recommendation.bestPaymentMethod"), value: paymentMethodLabel(paymentMethod))
                }
            }

            Section(language.text("recommendation.appliedBenefits")) {
                ForEach(recommendation.appliedBenefits) { benefit in
                    Link(destination: benefit.sourceURL) {
                        LabeledContent(benefit.title, value: benefit.valueYen, format: .currency(code: "JPY"))
                    }
                }
            }

            if !recommendation.warnings.isEmpty {
                Section(language.text("recommendation.checkpoints")) {
                    ForEach(recommendation.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Link(language.text("link.officialSite"), destination: recommendation.card.applicationURL)
            } footer: {
                Text(language.text("recommendation.officialTermsNote"))
            }
        }
        .navigationTitle(recommendation.card.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paymentMethodLabel(_ method: PaymentMethod) -> String {
        switch method {
        case .physical: language.text("payment.physical")
        case .contactless: language.text("payment.contactless")
        case .mobileContactless: language.text("payment.mobileContactless")
        case .applePay: "Apple Pay"
        case .mobileOrder: language.text("payment.mobileOrder")
        case .qr: language.text("payment.qr")
        case .online: language.text("payment.online")
        case .recurring: language.text("payment.recurring")
        }
    }
}
