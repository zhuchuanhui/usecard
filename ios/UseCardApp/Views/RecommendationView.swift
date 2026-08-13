import SwiftData
import SwiftUI
import UseCardCore

struct RecommendationView: View {
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
            AutomaticPlace(id: "aeon-group", title: "イオングループ", categoryID: "groceries", channel: .inStore),
            AutomaticPlace(id: "seven-eleven", title: "セブン-イレブン", categoryID: "general", channel: .inStore),
            AutomaticPlace(id: "amazon", title: "Amazon", categoryID: "online-shopping", channel: .online),
            AutomaticPlace(id: "rakuten-market", title: "楽天市場", categoryID: "online-shopping", channel: .online),
            AutomaticPlace(id: "jr-east-rail", title: "JR東日本の鉄道", categoryID: "transport", channel: .inStore)
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
                    ProgressView("カード情報を読み込み中")
                } else {
                    Text("金額入力なしで、主要な利用先を1万円利用時の条件で先回り比較しています。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(automaticRecommendations) { recommendation in
                        AutomaticPlaceRow(recommendation: recommendation)
                    }
                }
            } header: {
                Text("いつものおすすめ")
            } footer: {
                Text("実際の金額や日付が決まった時は、下の詳細比較で再計算してください。")
            }

            Section {
                DisclosureGroup("利用先・金額を指定して詳しく比較", isExpanded: $isDetailedExpanded) {
                    TextField("金額", value: $amountYen, format: .currency(code: "JPY"))
                        .keyboardType(.numberPad)

                    Picker("店舗", selection: $merchantID) {
                        Text("指定なし").tag("general")
                        Text("イオングループ").tag("aeon-group")
                        Text("セブン-イレブン").tag("seven-eleven")
                        Text("ローソン").tag("lawson")
                        Text("マクドナルド").tag("mcdonalds")
                        Text("モスバーガー").tag("mos-burger")
                        Text("ケンタッキーフライドチキン").tag("kfc")
                        Text("吉野家").tag("yoshinoya")
                        Text("サイゼリヤ").tag("saizeriya")
                        Text("ガスト").tag("gusto")
                        Text("すき家").tag("sukiya")
                        Text("はま寿司").tag("hamazushi")
                        Text("ドトール").tag("doutor")
                        Text("Amazon").tag("amazon")
                        Text("楽天市場").tag("rakuten-market")
                    }

                    Picker("用途", selection: $categoryID) {
                        Text("一般").tag("general")
                        Text("食料品").tag("groceries")
                        Text("飲食店").tag("dining")
                        Text("旅行").tag("travel")
                        Text("交通").tag("transport")
                        Text("公共料金").tag("utilities")
                        Text("オンライン通販").tag("online-shopping")
                    }

                    Picker("購入場所", selection: $channel) {
                        Text("店頭").tag(PurchaseChannel.inStore)
                        Text("オンライン").tag(PurchaseChannel.online)
                    }
                    .pickerStyle(.segmented)

                    Picker("頻度", selection: $frequency) {
                        Text("今回だけ").tag(SpendFrequency.once)
                        Text("毎月").tag(SpendFrequency.monthly)
                        Text("3か月ごと").tag(SpendFrequency.quarterly)
                        Text("毎年").tag(SpendFrequency.annually)
                    }

                    DatePicker("利用日", selection: $purchaseDate, displayedComponents: .date)

                    Button {
                        calculate()
                    } label: {
                        Label("一番お得なカードを調べる", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(catalogStore.catalog == nil || amountYen <= 0)
                }
            } header: {
                Text("必要な時だけ詳しく比較")
            }

            if let detailedResult {
                RecommendationSection(
                    title: "今使うなら",
                    emptyMessage: "条件に合う手持ちカードがありません",
                    items: detailedResult.bundle.owned,
                    paymentMethodByCardID: detailedResult.paymentMethodByCardID
                )
                RecommendationSection(
                    title: "新しく申し込むなら",
                    emptyMessage: "条件に合う申込可能カードがありません",
                    items: detailedResult.bundle.available,
                    paymentMethodByCardID: detailedResult.paymentMethodByCardID
                )
                AlternativePaymentSection(recommendations: alternativeRecommendations)
            }
        }
        .navigationTitle("おすすめ")
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
    let title: String
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
    let recommendation: AutomaticPlaceRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(recommendation.place.title)
                    .font(.headline)
                Spacer()
                Text("1万円基準")
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
                        Text("\(card.isOwned ? "保有カード" : "申込候補")・\(paymentMethodLabel(recommendation.paymentMethod))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(card.immediateValueYen, format: .currency(code: "JPY"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                }
            } else {
                Text("カードで比較できる情報がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let alternative = recommendation.alternative {
                Text("カード以外: \(alternative.product.paymentLabel)・約\(yen(alternative.immediateValueYen))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func paymentMethodLabel(_ method: PaymentMethod?) -> String {
        switch method {
        case .physical: "カード払い"
        case .contactless: "カードのタッチ決済"
        case .mobileContactless: "スマホのタッチ決済"
        case .applePay: "Apple Pay"
        case .mobileOrder: "モバイルオーダー"
        case .qr: "QR決済"
        case .online: "オンライン決済"
        case .recurring: "継続課金"
        case nil: "支払い方法確認中"
        }
    }

    private func yen(_ value: Double) -> String {
        value.formatted(.currency(code: "JPY"))
    }
}

private struct RecommendationSection: View {
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
                                Text("今回 \(item.immediateValueYen.formatted(.currency(code: "JPY")))・\(item.effectiveReturnPercent.formatted(.number.precision(.fractionLength(1))))%")
                                    .font(.subheadline)
                                if let method = paymentMethodByCardID[item.card.id] {
                                    Text(paymentMethodLabel(method))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if item.possibleImmediateValueYen > item.immediateValueYen {
                                    Text("条件達成時 最大\(item.possibleImmediateValueYen.formatted(.currency(code: "JPY")))")
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
        case .physical: "カード払い"
        case .contactless: "カードのタッチ決済"
        case .mobileContactless: "スマホのタッチ決済"
        case .applePay: "Apple Pay"
        case .mobileOrder: "モバイルオーダー"
        case .qr: "QR決済"
        case .online: "オンライン決済"
        case .recurring: "継続課金"
        }
    }
}

private struct AlternativePaymentSection: View {
    let recommendations: [AlternativePaymentRecommendation]

    var body: some View {
        Section {
            if recommendations.isEmpty {
                Text("この条件で確認できるカード以外の支払いはありません")
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
            Text("カード以外の支払い")
        } footer: {
            Text("カードからのチャージ還元や期間限定キャンペーンは二重計上していません。利用前に公式ルールを確認してください。")
        }
    }

    private func recommendationRow(_ recommendation: AlternativePaymentRecommendation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.product.name)
                    .font(.headline)
                Text(recommendation.product.paymentLabel)
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
    let recommendation: CardRecommendation
    let paymentMethod: PaymentMethod?

    var body: some View {
        List {
            Section("計算結果") {
                LabeledContent("今回の還元", value: recommendation.immediateValueYen, format: .currency(code: "JPY"))
                LabeledContent("実質還元率", value: recommendation.effectiveReturnPercent, format: .percent.scale(1).precision(.fractionLength(1)))
                LabeledContent("年換算・年会費控除後", value: recommendation.annualNetValueYen, format: .currency(code: "JPY"))
                if let paymentMethod {
                    LabeledContent("おすすめの支払い方法", value: paymentMethodLabel(paymentMethod))
                }
            }

            Section("適用された特典") {
                ForEach(recommendation.appliedBenefits) { benefit in
                    Link(destination: benefit.sourceURL) {
                        LabeledContent(benefit.title, value: benefit.valueYen, format: .currency(code: "JPY"))
                    }
                }
            }

            if !recommendation.warnings.isEmpty {
                Section("確認事項") {
                    ForEach(recommendation.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Link("公式サイトで確認", destination: recommendation.card.applicationURL)
            } footer: {
                Text("還元条件は変更される場合があります。申込・利用前に必ず公式情報を確認してください。")
            }
        }
        .navigationTitle(recommendation.card.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paymentMethodLabel(_ method: PaymentMethod) -> String {
        switch method {
        case .physical: "カード払い"
        case .contactless: "カードのタッチ決済"
        case .mobileContactless: "スマホのタッチ決済"
        case .applePay: "Apple Pay"
        case .mobileOrder: "モバイルオーダー"
        case .qr: "QR決済"
        case .online: "オンライン決済"
        case .recurring: "継続課金"
        }
    }
}
