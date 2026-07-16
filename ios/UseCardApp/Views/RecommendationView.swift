import SwiftData
import SwiftUI
import UseCardCore

struct RecommendationView: View {
    @Query(sort: \HoldingRecord.createdAt) private var holdingRecords: [HoldingRecord]
    let catalogStore: CatalogStore

    @State private var amountYen = 10_000.0
    @State private var merchantID = "general"
    @State private var categoryID = "general"
    @State private var paymentMethod = PaymentMethod.physical
    @State private var channel = PurchaseChannel.inStore
    @State private var frequency = SpendFrequency.once
    @State private var purchaseDate = Date()
    @State private var recommendations: RecommendationBundle?

    private let engine = RecommendationEngine()

    var body: some View {
        Form {
            if let warning = catalogStore.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Section("今回の買い物") {
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

                Picker("支払い方法", selection: $paymentMethod) {
                    Text("カード").tag(PaymentMethod.physical)
                    Text("カードのタッチ決済").tag(PaymentMethod.contactless)
                    Text("スマホのタッチ決済").tag(PaymentMethod.mobileContactless)
                    Text("Apple Pay").tag(PaymentMethod.applePay)
                    Text("モバイルオーダー").tag(PaymentMethod.mobileOrder)
                    Text("QR決済").tag(PaymentMethod.qr)
                    Text("オンライン").tag(PaymentMethod.online)
                    Text("継続課金").tag(PaymentMethod.recurring)
                }

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

            if holdingRecords.isEmpty {
                Section {
                    ContentUnavailableView(
                        "手持ちカードが未登録です",
                        systemImage: "creditcard",
                        description: Text("「手持ち」タブからカードを追加すると、今すぐ使えるカードを比較できます。")
                    )
                }
            }

            if let recommendations {
                RecommendationSection(
                    title: "今使うなら",
                    emptyMessage: "条件に合う手持ちカードがありません",
                    items: recommendations.owned
                )
                RecommendationSection(
                    title: "新しく申し込むなら",
                    emptyMessage: "条件に合う申込可能カードがありません",
                    items: recommendations.available
                )
            }
        }
        .navigationTitle("おすすめ")
        .overlay {
            if catalogStore.isLoading && catalogStore.catalog == nil {
                ProgressView("カード情報を読み込み中")
            }
        }
    }

    private func calculate() {
        guard let catalog = catalogStore.catalog else { return }
        let holdings = holdingRecords.map { record in
            let programID = catalog.products.first(where: { $0.id == record.cardID })?.pointProgramID
            return record.domainHolding(pointProgramID: programID)
        }
        let intent = PurchaseIntent(
            amountYen: amountYen,
            merchantID: merchantID == "general" ? nil : merchantID,
            categoryID: categoryID,
            paymentMethod: paymentMethod,
            channel: channel,
            frequency: frequency,
            purchaseDate: Self.dateFormatter.string(from: purchaseDate)
        )
        recommendations = engine.rank(catalog: catalog, intent: intent, holdings: holdings)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct RecommendationSection: View {
    let title: String
    let emptyMessage: String
    let items: [CardRecommendation]

    var body: some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        RecommendationDetailView(recommendation: item)
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
                                Text("今回 約\(item.immediateValueYen, format: .currency(code: "JPY"))・\(item.effectiveReturnPercent, format: .number.precision(.fractionLength(1)))%")
                                    .font(.subheadline)
                                if item.possibleImmediateValueYen > item.immediateValueYen {
                                    Text("条件達成時 最大\(item.possibleImmediateValueYen, format: .currency(code: "JPY"))")
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
}

private struct RecommendationDetailView: View {
    let recommendation: CardRecommendation

    var body: some View {
        List {
            Section("計算結果") {
                LabeledContent("今回の還元", value: recommendation.immediateValueYen, format: .currency(code: "JPY"))
                LabeledContent("実質還元率", value: recommendation.effectiveReturnPercent, format: .percent.scale(1).precision(.fractionLength(1)))
                LabeledContent("年換算・年会費控除後", value: recommendation.annualNetValueYen, format: .currency(code: "JPY"))
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
}
