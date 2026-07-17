import AppKit
import CryptoKit
import Foundation

let application = NSApplication.shared
let appDelegate = UseCardMacAppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()

fileprivate enum UseCardIconStyle: String {
    case standard
    case night

    static let defaultsKey = "jp.usecard.macos.app-icon-style"

    var label: String {
        switch self {
        case .standard: "通常"
        case .night: "夜"
        }
    }

    var resourceName: String {
        switch self {
        case .standard: "UseCard"
        case .night: "UseCardNight"
        }
    }

    static var saved: UseCardIconStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let style = UseCardIconStyle(rawValue: rawValue) else {
            return .standard
        }
        return style
    }
}

final class UseCardMacAppDelegate: NSObject, NSApplicationDelegate {
    private let model = MacAppModel()
    private var mainWindow: NSWindow?
    private var holdingsController: HoldingsViewController?
    private var catalogController: CatalogViewController?
    private var recommendationController: RecommendationViewController?
    private var dataController: DataViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationIcon(UseCardIconStyle.saved, persist: false)

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let recommendation = RecommendationViewController(model: model)
        let holdings = HoldingsViewController(model: model)
        let catalog = CatalogViewController(model: model)
        let data = DataViewController(
            model: model,
            iconStyle: UseCardIconStyle.saved,
            refreshAction: { [weak self] in self?.refreshCatalog() },
            changeIconAction: { [weak self] style in self?.applyApplicationIcon(style) }
        )
        recommendationController = recommendation
        holdingsController = holdings
        catalogController = catalog
        dataController = data

        tabs.addTabViewItem(tab(title: "おすすめ", image: "sparkles", controller: recommendation))
        tabs.addTabViewItem(tab(title: "手持ちカード", image: "wallet.pass", controller: holdings))
        tabs.addTabViewItem(tab(title: "カード一覧", image: "creditcard", controller: catalog))
        tabs.addTabViewItem(tab(title: "データ", image: "arrow.triangle.2.circlepath", controller: data))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_120, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = tabs
        window.title = "UseCard"
        window.setContentSize(NSSize(width: 1_120, height: 780))
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        mainWindow = window
        showMainWindow()

        refreshCatalog()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func showMainWindow() {
        guard let mainWindow else { return }
        if mainWindow.isMiniaturized {
            mainWindow.deminiaturize(nil)
        }
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func tab(title: String, image: String, controller: NSViewController) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: title)
        return item
    }

    private func refreshCatalog() {
        dataController?.setRefreshing(true)
        model.refreshCatalog { [weak self] in
            guard let self else { return }
            self.holdingsController?.reloadData()
            self.catalogController?.reloadData()
            self.recommendationController?.calculate()
            self.dataController?.setRefreshing(false)
        }
    }

    private func applyApplicationIcon(_ style: UseCardIconStyle, persist: Bool = true) {
        if persist {
            UserDefaults.standard.set(style.rawValue, forKey: UseCardIconStyle.defaultsKey)
        }
        guard let iconURL = Bundle.main.url(forResource: style.resourceName, withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApp.applicationIconImage = icon
    }
}

final class MacAppModel {
    private static let heldCardIDsKey = "jp.usecard.macos.held-card-ids"
    private static let retiredManualCardsKey = "jp.usecard.macos.manual-cards"
    private static let pendingCardsKey = "jp.usecard.macos.pending-official-cards"
    private let decoder = JSONDecoder()
    private let remoteBaseURL = URL(string: "https://zhuchuanhui.github.io/usecard/")!
    private let bundledOfficialLineups: [RemoteOfficialLineup]

    private(set) var catalog: CardCatalog?
    private(set) var catalogStatus = "同梱カタログを読み込みました"
    private(set) var heldCardIDs: Set<String>
    private var pendingCards: [PendingCardRecord]

    init() {
        bundledOfficialLineups = Self.loadBundledOfficialLineups()
        let savedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.heldCardIDsKey) ?? [])
        heldCardIDs = Set(savedIDs.filter { !$0.hasPrefix("manual-") })
        if heldCardIDs != savedIDs {
            UserDefaults.standard.set(Array(heldCardIDs).sorted(), forKey: Self.heldCardIDsKey)
        }
        UserDefaults.standard.removeObject(forKey: Self.retiredManualCardsKey)
        pendingCards = Self.loadPendingCards()
        loadBundledCatalog()
    }

    var products: [CardProduct] {
        let verified = catalog?.products ?? []
        let verifiedIdentities = Set(verified.map { cardIdentity(issuerID: $0.issuerID, name: $0.name) })
        let pending = pendingCards
            .filter { !verifiedIdentities.contains(cardIdentity(issuerID: $0.issuerID, name: $0.name)) }
            .map(pendingProduct)
        return (verified + pending).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func isHeld(_ cardID: String) -> Bool {
        heldCardIDs.contains(cardID)
    }

    func setHeld(_ isHeld: Bool, cardID: String) {
        if isHeld {
            heldCardIDs.insert(cardID)
        } else {
            heldCardIDs.remove(cardID)
        }
        UserDefaults.standard.set(Array(heldCardIDs).sorted(), forKey: Self.heldCardIDsKey)
    }

    fileprivate func recommend(intent: PurchaseIntent) -> RecommendationPresentation? {
        guard let catalog else { return nil }
        let holdings = heldCardIDs.map { UserHolding(cardID: $0) }
        let verifiedIDs = Set(catalog.products.map(\.id))
        let unverifiedHeldCards = products
            .filter { heldCardIDs.contains($0.id) && !verifiedIDs.contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedCompare($1) == .orderedAscending }
        return RecommendationPresentation(
            rankings: RecommendationEngine().rank(catalog: catalog, intent: intent, holdings: holdings),
            unverifiedHeldCardNames: unverifiedHeldCards
        )
    }

    fileprivate func lookupOfficialCandidates(
        named query: String,
        completion: @escaping (Result<[RemoteCardSearchEntry], Error>) -> Void
    ) {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else {
            completion(.success([]))
            return
        }
        let catalogProducts = catalog?.products ?? []
        let group = DispatchGroup()
        let lock = NSLock()
        var indexedEntries: [RemoteCardSearchEntry] = []
        var registryEntries: [RemoteIssuerEntry] = []
        var officialLineups = bundledOfficialLineups

        func fetch<T: Decodable>(_ url: URL, type: T.Type, assign: @escaping (T) -> Void) {
            group.enter()
            URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
                defer { group.leave() }
                guard let self, let data else { return }
                do {
                    try self.requireSuccessfulResponse(response)
                    let decoded = try self.decoder.decode(T.self, from: data)
                    lock.lock()
                    assign(decoded)
                    lock.unlock()
                } catch {
                    // A stale offline bundle can still supply known official domains.
                }
            }.resume()
        }

        fetch(remoteBaseURL.appending(path: "search-index.json"), type: [RemoteCardSearchEntry].self) {
            indexedEntries = $0
        }
        fetch(remoteBaseURL.appending(path: "issuers.json"), type: [RemoteIssuerEntry].self) {
            registryEntries = $0
        }
        fetch(remoteBaseURL.appending(path: "official-lineups.json"), type: [RemoteOfficialLineup].self) {
            officialLineups = $0
        }

        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self else { return }
            let cached = self.cachedMatches(for: normalizedQuery, in: indexedEntries)
            let lineupCandidates = self.officialLineupCandidates(for: query, in: officialLineups)
            let officialIssuers = self.officialIssuers(registry: registryEntries, catalogProducts: catalogProducts)
            self.fetchSaisonLineupCandidates(for: query) { saisonLineup in
                self.searchOfficialWeb(
                    for: query,
                    issuers: officialIssuers,
                    catalogProducts: catalogProducts
                ) { online in
                    let related = self.knownRelatedCandidates(for: query)
                    let candidates = self.deduplicateCandidates(
                        related + lineupCandidates + saisonLineup + cached + online,
                        excluding: catalogProducts
                    )
                    DispatchQueue.main.async { completion(.success(candidates)) }
                }
            }
        }
    }

    fileprivate func addPendingCard(_ entry: RemoteCardSearchEntry) {
        if let verified = catalog?.products.first(where: {
            cardIdentity(issuerID: $0.issuerID, name: $0.name) == cardIdentity(issuerID: entry.issuerID, name: entry.name)
        }) {
            setHeld(true, cardID: verified.id)
            return
        }
        if let existing = pendingCards.first(where: {
            cardIdentity(issuerID: $0.issuerID, name: $0.name) == cardIdentity(issuerID: entry.issuerID, name: entry.name)
        }) {
            setHeld(true, cardID: existing.id)
            return
        }
        let pending = PendingCardRecord(
            id: "pending-\(UUID().uuidString.lowercased())",
            issuerID: entry.issuerID,
            issuerName: entry.issuerName,
            name: entry.name,
            officialURL: entry.officialURL,
            observedAt: entry.observedAt
        )
        pendingCards.append(pending)
        savePendingCards()
        setHeld(true, cardID: pending.id)
    }

    func refreshCatalog(completion: @escaping () -> Void) {
        let manifestURL = remoteBaseURL.appending(path: "manifest.json")
        URLSession.shared.dataTask(with: manifestURL) { [weak self] manifestData, manifestResponse, error in
            guard let self else { return }
            do {
                if let error { throw error }
                guard let manifestData else { throw CatalogRefreshError.badResponse }
                try self.requireSuccessfulResponse(manifestResponse)
                let manifest = try self.decoder.decode(RemoteManifest.self, from: manifestData)
                guard manifest.schemaVersion == 1 else { throw CatalogRefreshError.unsupportedSchema }

                let catalogURL = self.remoteBaseURL.appending(path: manifest.path)
                URLSession.shared.dataTask(with: catalogURL) { [weak self] catalogData, catalogResponse, error in
                    guard let self else { return }
                    let result: Result<CardCatalog, Error> = Result {
                        if let error { throw error }
                        guard let catalogData else { throw CatalogRefreshError.badResponse }
                        try self.requireSuccessfulResponse(catalogResponse)
                        guard self.sha256(catalogData) == manifest.sha256 else { throw CatalogRefreshError.checksumMismatch }
                        let catalog = try self.decoder.decode(CardCatalog.self, from: catalogData)
                        guard catalog.schemaVersion == 1, catalog.version == manifest.catalogVersion else {
                            throw CatalogRefreshError.manifestMismatch
                        }
                        if let current = self.catalog, catalog.version < current.version {
                            throw CatalogRefreshError.olderThanBundledCatalog
                        }
                        return catalog
                    }
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let catalog):
                            self.catalog = catalog
                            self.reconcilePendingCards()
                            self.catalogStatus = "自動更新データ: \(catalog.version)"
                case .failure(let error):
                    if case CatalogRefreshError.olderThanBundledCatalog = error {
                        self.catalogStatus = "同梱カタログが配信版より新しいため、同梱版を使用中"
                    } else {
                        self.catalogStatus = "更新サーバーに接続できないため、同梱カタログを使用中"
                    }
                        }
                        completion()
                    }
                }.resume()
            } catch {
                DispatchQueue.main.async {
                    self.catalogStatus = "更新サーバーに接続できないため、同梱カタログを使用中"
                    completion()
                }
            }
        }.resume()
    }

    private func loadBundledCatalog() {
        do {
            guard let url = Bundle.main.url(forResource: "latest", withExtension: "json") else {
                throw CatalogRefreshError.missingBundledCatalog
            }
            catalog = try decoder.decode(CardCatalog.self, from: Data(contentsOf: url))
            reconcilePendingCards()
        } catch {
            catalogStatus = "同梱カタログを読み込めません"
        }
    }

    private func requireSuccessfulResponse(_ response: URLResponse?) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw CatalogRefreshError.badResponse
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func reconcilePendingCards() {
        guard let catalog else { return }
        var reconciled = false
        pendingCards.removeAll { pending in
            guard let verified = catalog.products.first(where: {
                cardIdentity(issuerID: $0.issuerID, name: $0.name) == cardIdentity(issuerID: pending.issuerID, name: pending.name)
            }) else {
                return false
            }
            if heldCardIDs.remove(pending.id) != nil {
                heldCardIDs.insert(verified.id)
                UserDefaults.standard.set(Array(heldCardIDs).sorted(), forKey: Self.heldCardIDsKey)
            }
            reconciled = true
            return true
        }
        if reconciled { savePendingCards() }
    }

    private func pendingProduct(_ pending: PendingCardRecord) -> CardProduct {
        CardProduct(
            id: pending.id,
            issuerID: pending.issuerID,
            issuerName: pending.issuerName,
            name: pending.name,
            networks: [],
            annualFeeYen: 0,
            applicationStatus: .suspended,
            applicationURL: pending.officialURL,
            eligibilityNote: "公式ページを確認済みです。還元条件を検証中のため、おすすめ計算には使用しません。",
            pointProgramID: nil,
            benefitRules: [],
            sources: [
                SourceEvidence(
                    url: pending.officialURL,
                    observedAt: pending.observedAt,
                    contentHash: pending.id,
                    freshness: .stale
                )
            ]
        )
    }

    private func cardIdentity(issuerID: String, name: String) -> String {
        "\(issuerID):\(normalizedSearchText(name))"
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: #"[\s　・()（）\[\]［］-]"#, with: "", options: .regularExpression)
    }

    private func cachedMatches(for query: String, in entries: [RemoteCardSearchEntry]) -> [RemoteCardSearchEntry] {
        let terms = relatedSearchTerms(for: query).map(normalizedSearchText)
        return entries.filter { entry in
            let cardName = normalizedSearchText(entry.name)
            let issuerName = normalizedSearchText(entry.issuerName)
            return terms.contains { term in
                !term.isEmpty && (cardName.contains(term) || issuerName.contains(term) || term.contains(cardName))
            }
        }
    }

    private func officialLineupCandidates(
        for query: String,
        in lineups: [RemoteOfficialLineup]
    ) -> [RemoteCardSearchEntry] {
        let terms = relatedSearchTerms(for: query)
            .map(normalizedSearchText)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        return lineups.flatMap { lineup in
            let issuerTerms = ([lineup.issuerName] + lineup.aliases)
                .map(normalizedSearchText)
                .filter { !$0.isEmpty }
            let issuerMatches = terms.contains { term in
                issuerTerms.contains { issuerTerm in
                    issuerTerm.contains(term) || term.contains(issuerTerm)
                }
            }
            return lineup.cards.compactMap { card -> RemoteCardSearchEntry? in
                let name = normalizedSearchText(card.name)
                let nameMatches = terms.contains { term in name.contains(term) || term.contains(name) }
                guard issuerMatches || nameMatches else { return nil }
                return RemoteCardSearchEntry(
                    issuerID: card.issuerID ?? lineup.issuerID,
                    issuerName: card.issuerName ?? lineup.issuerName,
                    name: card.name,
                    officialURL: card.officialURL,
                    observedAt: lineup.observedAt,
                    discovery: "公式ラインナップ"
                )
            }
        }
    }

    private func knownRelatedCandidates(for query: String) -> [RemoteCardSearchEntry] {
        let normalized = normalizedSearchText(query)
        var candidates: [RemoteCardSearchEntry] = []
        if normalized.contains("三井住友カードnl") {
            candidates.append(RemoteCardSearchEntry(
                issuerID: "smbc-card",
                issuerName: "三井住友カード株式会社",
                name: "三井住友カード ゴールド（NL）",
                officialURL: URL(string: "https://www.smbc-card.com/nyukai/card/gold-numberless.jsp")!,
                observedAt: ISO8601DateFormatter().string(from: Date()),
                discovery: "公式の関連カード定義"
            ))
        }
        if isSaisonQuery(query) {
            candidates.append(RemoteCardSearchEntry(
                issuerID: "credit-saison",
                issuerName: "株式会社クレディセゾン",
                name: "SAISON GOLD Premium",
                officialURL: URL(string: "https://www.saisoncard.co.jp/creditcard/lineup/102/")!,
                observedAt: ISO8601DateFormatter().string(from: Date()),
                discovery: "公式のカード定義"
            ))
        }
        return candidates
    }

    private func isSaisonQuery(_ query: String) -> Bool {
        let normalized = normalizedSearchText(query)
        guard normalized.count >= 3 else { return false }
        return normalized.contains("saison")
            || "saison".contains(normalized)
            || normalized.contains("セゾン")
            || "セゾン".contains(normalized)
    }

    private func fetchSaisonLineupCandidates(
        for query: String,
        completion: @escaping ([RemoteCardSearchEntry]) -> Void
    ) {
        let lineupURL = URL(string: "https://www.saisoncard.co.jp/creditcard/lineup/")!
        var request = URLRequest(url: lineupURL)
        request.setValue("UseCard/1.0 (official card catalog lookup)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, let data else {
                completion([])
                return
            }
            guard (try? self.requireSuccessfulResponse(response)) != nil else {
                completion([])
                return
            }
            let lineup = self.parseSaisonLineupCandidates(from: data)
            completion(self.matchingSaisonLineupCandidates(lineup, for: query))
        }.resume()
    }

    private func matchingSaisonLineupCandidates(
        _ candidates: [RemoteCardSearchEntry],
        for query: String
    ) -> [RemoteCardSearchEntry] {
        if isSaisonQuery(query) { return candidates }
        let terms = relatedSearchTerms(for: query)
            .map(normalizedSearchText)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return candidates.filter { candidate in
            let candidateName = normalizedSearchText(candidate.name)
            return terms.contains { candidateName.contains($0) }
        }
    }

    private func parseSaisonLineupCandidates(from data: Data) -> [RemoteCardSearchEntry] {
        guard let html = String(data: data, encoding: .utf8),
              let expression = try? NSRegularExpression(
                pattern: #"<a\s+[^>]*href="([^"]*/creditcard/lineup/[^"?#]+/?)[^"]*"[^>]*>([^<]+)</a>"#,
                options: [.caseInsensitive]
              ) else {
            return []
        }

        let pageURL = URL(string: "https://www.saisoncard.co.jp/creditcard/lineup/")!
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var seenURLs = Set<String>()
        var candidates: [RemoteCardSearchEntry] = []
        expression.enumerateMatches(in: html, options: [], range: htmlRange) { match, _, _ in
            guard let match,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html),
                  let officialURL = URL(string: String(html[hrefRange]), relativeTo: pageURL)?.absoluteURL else {
                return
            }
            let name = self.decodedHTMLText(String(html[nameRange]))
            guard !name.isEmpty, seenURLs.insert(officialURL.absoluteString).inserted else { return }
            candidates.append(RemoteCardSearchEntry(
                issuerID: "credit-saison",
                issuerName: "株式会社クレディセゾン",
                name: name,
                officialURL: officialURL,
                observedAt: ISO8601DateFormatter().string(from: Date()),
                discovery: "公式ラインナップ"
            ))
        }
        return candidates
    }

    private func decodedHTMLText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func relatedSearchTerms(for query: String) -> [String] {
        let spacedVariant = query
            .replacingOccurrences(of: #"[（()）]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutVariant = query
            .replacingOccurrences(of: #"[（(][^）)]*[）)]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(Set([query, spacedVariant, withoutVariant])).filter { !$0.isEmpty }
    }

    private func officialIssuers(
        registry: [RemoteIssuerEntry],
        catalogProducts: [CardProduct]
    ) -> [OfficialIssuer] {
        var issuers = registry.compactMap { entry -> OfficialIssuer? in
            guard let host = canonicalHost(entry.officialURL) else { return nil }
            return OfficialIssuer(id: entry.id, name: entry.name, host: host, aliases: [])
        }
        issuers += catalogProducts.compactMap { product -> OfficialIssuer? in
            guard let host = canonicalHost(product.applicationURL) else { return nil }
            return OfficialIssuer(id: product.issuerID, name: product.issuerName, host: host, aliases: [])
        }
        issuers += [
            OfficialIssuer(
                id: "credit-saison",
                name: "株式会社クレディセゾン",
                host: "saisoncard.co.jp",
                aliases: ["saison", "セゾン"]
            ),
            OfficialIssuer(
                id: "viewcard",
                name: "株式会社ビューカード",
                host: "jreast.co.jp",
                aliases: ["view", "ビュー", "ビューカード"]
            )
        ]
        var seen = Set<String>()
        return issuers.filter { seen.insert("\($0.id):\($0.host)").inserted }
    }

    private func searchOfficialWeb(
        for query: String,
        issuers: [OfficialIssuer],
        catalogProducts: [CardProduct],
        completion: @escaping ([RemoteCardSearchEntry]) -> Void
    ) {
        let terms = relatedSearchTerms(for: query)
        let normalizedTerms = terms.map(normalizedSearchText)
        let matchingIssuers = issuers.filter { issuer in
            let issuerName = normalizedSearchText(issuer.name)
            return normalizedTerms.contains { term in
                issuerName.contains(term)
                    || term.contains(issuerName)
                    || issuer.aliases.contains { alias in
                        let normalizedAlias = self.normalizedSearchText(alias)
                        return term.count >= 3 && (normalizedAlias.contains(term) || term.contains(normalizedAlias))
                    }
            }
                || catalogProducts.contains { product in
                    product.issuerID == issuer.id && normalizedTerms.contains { term in
                        let name = normalizedSearchText(product.name)
                        return name.contains(term) || term.contains(name)
                    }
                }
        }
        let relatedTerm = query
            .replacingOccurrences(of: #"[（()）]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var searchTerms: [String] = []
        if !normalizedSearchText(relatedTerm).contains("ゴールド") {
            searchTerms.append("\(relatedTerm) ゴールド クレジットカード 公式")
        }
        searchTerms.append("\(query) クレジットカード 公式")
        for issuer in matchingIssuers.prefix(2) {
            if !normalizedSearchText(relatedTerm).contains("ゴールド") {
                searchTerms.append("site:\(issuer.host) \(relatedTerm) ゴールド クレジットカード")
            }
            searchTerms.append("site:\(issuer.host) \(relatedTerm) クレジットカード")
        }
        var seenTerms = Set<String>()
        let distinctTerms = searchTerms.filter { seenTerms.insert($0).inserted }.prefix(4)
        guard !distinctTerms.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var candidates: [RemoteCardSearchEntry] = []
        for issuer in matchingIssuers.prefix(2) {
            let sourceCards = catalogProducts.filter { product in
                guard let host = self.canonicalHost(product.applicationURL) else { return false }
                return host == issuer.host || host.hasSuffix(".\(issuer.host)")
            }
            let signatures = Set(sourceCards.flatMap { self.pathSignatures(for: $0.applicationURL) })
            guard !signatures.isEmpty, let sitemapURL = self.sitemapURL(for: issuer) else { continue }
            var sitemapRequest = URLRequest(url: sitemapURL)
            sitemapRequest.timeoutInterval = 15
            sitemapRequest.setValue("UseCardCatalog/1.0", forHTTPHeaderField: "User-Agent")
            group.enter()
            URLSession.shared.dataTask(with: sitemapRequest) { [weak self] data, response, _ in
                defer { group.leave() }
                guard let self, let data else { return }
                guard (try? self.requireSuccessfulResponse(response)) != nil else { return }
                let matchingURLs = SitemapParser.urls(from: data).filter { url in
                    let path = url.path.lowercased()
                    return path.contains("gold")
                        && !path.contains("/camp/")
                        && signatures.contains { path.contains($0) }
                }
                let related = matchingURLs.prefix(3).compactMap { url -> RemoteCardSearchEntry? in
                    guard let source = sourceCards.first(where: { self.signaturesForURL($0.applicationURL, match: url) }) else {
                        return nil
                    }
                    return RemoteCardSearchEntry(
                        issuerID: source.issuerID,
                        issuerName: source.issuerName,
                        name: self.goldVariantName(from: source.name),
                        officialURL: url,
                        observedAt: ISO8601DateFormatter().string(from: Date()),
                        discovery: "発行会社公式サイトマップ"
                    )
                }
                lock.lock()
                candidates.append(contentsOf: related)
                lock.unlock()
            }.resume()
        }
        for term in distinctTerms {
            guard let url = bingRSSURL(for: term) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("UseCard/1.0 (+https://zhuchuanhui.github.io/usecard/)", forHTTPHeaderField: "User-Agent")
            group.enter()
            URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                defer { group.leave() }
                guard let self, let data else { return }
                guard (try? self.requireSuccessfulResponse(response)) != nil else { return }
                let results = BingRSSParser.items(from: data)
                let verified = results.compactMap { result -> RemoteCardSearchEntry? in
                    guard self.isLikelyCardProduct(result),
                          let issuer = self.officialIssuer(for: result.url, in: issuers) else { return nil }
                    return RemoteCardSearchEntry(
                        issuerID: issuer.id,
                        issuerName: issuer.name,
                        name: self.cleanOnlineResultTitle(result.title),
                        officialURL: result.url,
                        observedAt: ISO8601DateFormatter().string(from: Date()),
                        discovery: "オンラインの公式サイト検索"
                    )
                }
                lock.lock()
                candidates.append(contentsOf: verified)
                lock.unlock()
            }.resume()
        }
        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self else { return }
            completion(self.deduplicateCandidates(candidates, excluding: catalogProducts))
        }
    }

    private func bingRSSURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.bing.com/search")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "rss"),
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }

    private func sitemapURL(for issuer: OfficialIssuer) -> URL? {
        URL(string: "https://\(issuer.host)/sitemap.xml")
    }

    private func pathSignatures(for url: URL) -> [String] {
        let ignored = Set(["card", "cards", "index", "html", "htm", "jsp", "php", "apply", "nyukai"])
        return url.path.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !ignored.contains($0) }
    }

    private func signaturesForURL(_ sourceURL: URL, match candidateURL: URL) -> Bool {
        let candidatePath = candidateURL.path.lowercased()
        return pathSignatures(for: sourceURL).contains { candidatePath.contains($0) }
    }

    private func goldVariantName(from cardName: String) -> String {
        if let range = cardName.range(of: #"[（(]"#, options: .regularExpression) {
            return "\(cardName[..<range.lowerBound]) ゴールド\(cardName[range.lowerBound...])"
        }
        return "\(cardName) ゴールド"
    }

    private func officialIssuer(for url: URL, in issuers: [OfficialIssuer]) -> OfficialIssuer? {
        guard let host = canonicalHost(url) else { return nil }
        return issuers.first { host == $0.host || host.hasSuffix(".\($0.host)") }
    }

    private func canonicalHost(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func isLikelyCardProduct(_ result: BingRSSItem) -> Bool {
        let title = result.title.precomposedStringWithCompatibilityMapping
        let path = result.url.path.lowercased()
        guard title.range(of: "カード", options: .caseInsensitive) != nil
            || title.range(of: "card", options: .caseInsensitive) != nil else { return false }
        return !path.contains("/camp/")
            && !path.contains("/login")
            && !path.contains("/mem/")
            && !path.contains("/customer-support/")
    }

    private func cleanOnlineResultTitle(_ title: String) -> String {
        let cleaned = title
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(100))
    }

    private func deduplicateCandidates(
        _ candidates: [RemoteCardSearchEntry],
        excluding catalogProducts: [CardProduct]
    ) -> [RemoteCardSearchEntry] {
        let knownIdentities = Set(catalogProducts.map { cardIdentity(issuerID: $0.issuerID, name: $0.name) })
        var seen = Set<String>()
        let unique = candidates.filter { candidate in
            let identity = cardIdentity(issuerID: candidate.issuerID, name: candidate.name)
            return !knownIdentities.contains(identity) && seen.insert(identity).inserted
        }
        return unique.sorted { left, right in
            let leftPriority = left.discovery?.contains("公式") == true ? 0 : 1
            let rightPriority = right.discovery?.contains("公式") == true ? 0 : 1
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            let leftIsGold = left.name.localizedCaseInsensitiveContains("ゴールド")
            let rightIsGold = right.name.localizedCaseInsensitiveContains("ゴールド")
            if leftIsGold != rightIsGold { return leftIsGold }
            return left.name.localizedCompare(right.name) == .orderedAscending
        }
    }

    private static func loadPendingCards() -> [PendingCardRecord] {
        guard let data = UserDefaults.standard.data(forKey: pendingCardsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingCardRecord].self, from: data)) ?? []
    }

    private static func loadBundledOfficialLineups() -> [RemoteOfficialLineup] {
        guard let url = Bundle.main.url(forResource: "official-lineups", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([RemoteOfficialLineup].self, from: data)) ?? []
    }

    private func savePendingCards() {
        let data = try? JSONEncoder().encode(pendingCards)
        UserDefaults.standard.set(data, forKey: Self.pendingCardsKey)
    }

}

private struct RecommendationPresentation {
    let rankings: RecommendationBundle
    let unverifiedHeldCardNames: [String]
}

private struct RemoteManifest: Decodable {
    let schemaVersion: Int
    let catalogVersion: String
    let path: String
    let sha256: String
}

fileprivate struct RemoteCardSearchEntry: Decodable, Hashable {
    let issuerID: String
    let issuerName: String
    let name: String
    let officialURL: URL
    let observedAt: String
    let discovery: String?
}

private struct RemoteIssuerEntry: Decodable {
    let id: String
    let name: String
    let officialURL: URL
}

private struct RemoteOfficialLineup: Decodable {
    let issuerID: String
    let issuerName: String
    let aliases: [String]
    let sourceURL: URL
    let observedAt: String
    let cards: [RemoteOfficialLineupCard]
}

private struct RemoteOfficialLineupCard: Decodable {
    let issuerID: String?
    let issuerName: String?
    let name: String
    let officialURL: URL
}

private struct OfficialIssuer: Hashable {
    let id: String
    let name: String
    let host: String
    let aliases: [String]
}

private struct BingRSSItem {
    let title: String
    let url: URL
}

private final class BingRSSParser: NSObject, XMLParserDelegate {
    private var items: [BingRSSItem] = []
    private var isInItem = false
    private var currentElement = ""
    private var title = ""
    private var link = ""

    static func items(from data: Data) -> [BingRSSItem] {
        let parser = XMLParser(data: data)
        let delegate = BingRSSParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.items : []
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item" {
            isInItem = true
            title = ""
            link = ""
        }
        if isInItem && (elementName == "title" || elementName == "link") {
            currentElement = elementName
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInItem else { return }
        if currentElement == "title" { title += string }
        if currentElement == "link" { link += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            if let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) {
                items.append(BingRSSItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: url))
            }
            isInItem = false
            currentElement = ""
        } else if elementName == currentElement {
            currentElement = ""
        }
    }
}

private final class SitemapParser: NSObject, XMLParserDelegate {
    private var urls: [URL] = []
    private var isInLocation = false
    private var location = ""

    static func urls(from data: Data) -> [URL] {
        let parser = XMLParser(data: data)
        let delegate = SitemapParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.urls : []
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "loc" {
            isInLocation = true
            location = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInLocation { location += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "loc" else { return }
        if let url = URL(string: location.trimmingCharacters(in: .whitespacesAndNewlines)) {
            urls.append(url)
        }
        isInLocation = false
    }
}

private struct PendingCardRecord: Codable, Hashable {
    let id: String
    let issuerID: String
    let issuerName: String
    let name: String
    let officialURL: URL
    let observedAt: String
}

private enum CatalogRefreshError: Error {
    case missingBundledCatalog
    case badResponse
    case unsupportedSchema
    case checksumMismatch
    case manifestMismatch
    case olderThanBundledCatalog
}

final class RecommendationViewController: NSViewController {
    private enum PanelTone {
        case standard
        case emphasized
        case subdued
    }

    private let model: MacAppModel
    private let amountField = NSTextField(string: "10000")
    private let merchantPopup = NSPopUpButton()
    private let categoryPopup = NSPopUpButton()
    private let paymentPopup = NSPopUpButton()
    private let channelPopup = NSPopUpButton()
    private let frequencyPopup = NSPopUpButton()
    private let datePicker = NSDatePicker()
    private let applicationPopup = NSPopUpButton()
    private let applicationButton = NSButton(title: "公式申込ページを開く", target: nil, action: nil)
    private let resultStack = NSStackView()
    private let contentScroll = NSScrollView()
    private let scrollDocumentView = NSView()
    private let rootStack = NSStackView()
    private var applicationCandidates: [CardRecommendation] = []
    private var isSizingScrollableContent = false
    private var shouldScrollToTop = true

    private let merchants = [
        ("general", "指定なし"), ("aeon-group", "イオングループ"), ("seven-eleven", "セブン-イレブン"),
        ("lawson", "ローソン"), ("mcdonalds", "マクドナルド"), ("mos-burger", "モスバーガー"),
        ("kfc", "ケンタッキーフライドチキン"), ("yoshinoya", "吉野家"), ("saizeriya", "サイゼリヤ"),
        ("gusto", "ガスト"), ("sukiya", "すき家"), ("hamazushi", "はま寿司"),
        ("doutor", "ドトール"), ("amazon", "Amazon"), ("rakuten-market", "楽天市場")
    ]
    private let categories = [
        ("general", "一般"), ("groceries", "食料品"), ("dining", "飲食店"), ("travel", "旅行"),
        ("transport", "交通"), ("utilities", "公共料金"), ("online-shopping", "オンライン通販")
    ]
    private let paymentMethods: [(PaymentMethod, String)] = [
        (.physical, "カード"), (.contactless, "カードのタッチ決済"), (.mobileContactless, "スマホのタッチ決済"),
        (.applePay, "Apple Pay"), (.mobileOrder, "モバイルオーダー"), (.qr, "QR決済"),
        (.online, "オンライン"), (.recurring, "継続課金")
    ]
    private let channels: [(PurchaseChannel, String)] = [(.inStore, "店頭"), (.online, "オンライン")]
    private let frequencies: [(SpendFrequency, String)] = [(.once, "今回だけ"), (.monthly, "毎月"), (.quarterly, "3か月ごと"), (.annually, "毎年")]

    init(model: MacAppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "おすすめ"
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.autohidesScrollers = true
        scrollDocumentView.wantsLayer = true
        scrollDocumentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        scrollDocumentView.frame = NSRect(x: 0, y: 0, width: 1_120, height: 780)
        contentScroll.documentView = scrollDocumentView

        let root = rootStack
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 14
        root.frame = NSRect(x: 28, y: 22, width: 1_064, height: 1)
        scrollDocumentView.addSubview(root)
        func addFullWidth(_ view: NSView) {
            root.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        let headline = NSStackView()
        headline.orientation = .vertical
        headline.alignment = .leading
        headline.spacing = 3
        let heading = NSTextField(labelWithString: "支払いに、いちばん強い1枚を")
        heading.font = .systemFont(ofSize: 25, weight: .bold)
        let subtitle = NSTextField(labelWithString: "条件に合う公式還元ルールだけで、保有カードと申込候補を比較します。")
        subtitle.textColor = .secondaryLabelColor
        headline.addArrangedSubview(heading)
        headline.addArrangedSubview(subtitle)
        addFullWidth(headline)

        setupPopups()
        amountField.alignment = .right
        datePicker.datePickerElements = .yearMonthDay
        datePicker.dateValue = Date()
        let calculateButton = NSButton(title: "この条件で比べる", target: self, action: #selector(calculate))
        calculateButton.bezelStyle = .rounded
        calculateButton.controlSize = .large
        let conditionContent = NSStackView()
        conditionContent.orientation = .vertical
        conditionContent.alignment = .width
        conditionContent.spacing = 12
        func addConditionFullWidth(_ view: NSView) {
            conditionContent.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: conditionContent.widthAnchor).isActive = true
        }
        addConditionFullWidth(panelHeading("利用条件", detail: "店舗・支払い方法まで選ぶと、対象特典を正確に比較できます。"))
        addConditionFullWidth(formRow([
            formField("金額", control: amountField),
            formField("店舗", control: merchantPopup),
            formField("用途", control: categoryPopup)
        ]))
        addConditionFullWidth(formRow([
            formField("支払い方法", control: paymentPopup),
            formField("購入場所", control: channelPopup),
            formField("頻度", control: frequencyPopup)
        ]))
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .bottom
        actionRow.spacing = 12
        actionRow.addArrangedSubview(formField("利用日", control: datePicker))
        actionRow.addArrangedSubview(calculateButton)
        calculateButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        addConditionFullWidth(actionRow)
        addFullWidth(panel(containing: conditionContent, tone: .standard))

        addFullWidth(panelHeading("おすすめ", detail: "最適な1枚を先に表示し、次点だけをコンパクトに比較します。"))
        configureResultStack()
        addFullWidth(resultStack)

        let applicationRow = NSStackView()
        applicationRow.orientation = .horizontal
        applicationRow.alignment = .centerY
        applicationRow.spacing = 10
        applicationRow.addArrangedSubview(panelHeading("申込候補", detail: "公式ページを開く前に候補を切り替えられます。"))
        applicationPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 270).isActive = true
        applicationRow.addArrangedSubview(applicationPopup)
        applicationButton.target = self
        applicationButton.action = #selector(openApplicationPage)
        applicationButton.isEnabled = false
        applicationRow.addArrangedSubview(applicationButton)
        addFullWidth(panel(containing: applicationRow, tone: .subdued))
        view = contentScroll
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        calculate()
        resizeScrollableContent()
        scrollToTopIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        resizeScrollableContent()
    }

    @objc func calculate() {
        let amount = Double(amountField.stringValue.filter { $0.isNumber }) ?? 0
        guard amount > 0 else {
            renderMessage("金額を入力してください。", detail: "比較する利用額を入力すると、お得額と還元率を計算します。")
            updateApplicationCandidates([])
            return
        }
        let merchant = merchants[merchantPopup.indexOfSelectedItem].0
        let category = categories[categoryPopup.indexOfSelectedItem].0
        let intent = PurchaseIntent(
            amountYen: amount,
            merchantID: merchant == "general" ? nil : merchant,
            categoryID: category,
            paymentMethod: paymentMethods[paymentPopup.indexOfSelectedItem].0,
            channel: channels[channelPopup.indexOfSelectedItem].0,
            frequency: frequencies[frequencyPopup.indexOfSelectedItem].0,
            purchaseDate: dateString(datePicker.dateValue)
        )
        guard let presentation = model.recommend(intent: intent) else {
            renderMessage("カタログを読み込めません。", detail: "データ画面から最新カタログを確認してください。")
            updateApplicationCandidates([])
            return
        }
        renderRecommendations(presentation)
        updateApplicationCandidates(Array(presentation.rankings.available.prefix(5)))
    }

    private func setupPopups() {
        merchantPopup.addItems(withTitles: merchants.map(\.1))
        categoryPopup.addItems(withTitles: categories.map(\.1))
        paymentPopup.addItems(withTitles: paymentMethods.map(\.1))
        channelPopup.addItems(withTitles: channels.map(\.1))
        frequencyPopup.addItems(withTitles: frequencies.map(\.1))
    }

    private func configureResultStack() {
        resultStack.orientation = .vertical
        resultStack.alignment = .width
        resultStack.spacing = 10
        resultStack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private func renderRecommendations(_ presentation: RecommendationPresentation) {
        clearResultCards()
        if !presentation.unverifiedHeldCardNames.isEmpty {
            addResultView(noticeCard(
                title: "確認待ちの保有カード",
                detail: "\(presentation.unverifiedHeldCardNames.joined(separator: "・")) は還元条件を検証中のため、順位に混ぜていません。"
            ))
        }

        let rankings = presentation.rankings
        addRecommendationSection(
            title: "手持ちで、いま一番お得",
            detail: "保有カードだけで比較",
            recommendations: rankings.owned,
            emptyTitle: "比較できる保有カードがありません",
            emptyDetail: "手持ちカードから公式確認済みのカードを登録すると、ここに最適な1枚を表示します。"
        )
        addRecommendationSection(
            title: "新しく申し込むなら",
            detail: "年会費を差し引いた候補",
            recommendations: rankings.available,
            emptyTitle: "条件に合う申込候補がありません",
            emptyDetail: "条件を変えるか、カタログ更新後にもう一度比較してください。"
        )
        resizeScrollableContent()
    }

    private func renderMessage(_ title: String, detail: String) {
        clearResultCards()
        addResultView(noticeCard(title: title, detail: detail))
        resizeScrollableContent()
    }

    private func clearResultCards() {
        for view in resultStack.arrangedSubviews {
            resultStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func resizeScrollableContent() {
        guard !isSizingScrollableContent else { return }
        let visibleWidth = contentScroll.contentView.bounds.width
        guard visibleWidth > 0 else { return }

        isSizingScrollableContent = true
        defer { isSizingScrollableContent = false }

        let rootWidth = max(visibleWidth - 56, 1)
        rootStack.setFrameSize(NSSize(width: rootWidth, height: max(rootStack.frame.height, 1)))
        rootStack.layoutSubtreeIfNeeded()
        let rootHeight = max(rootStack.fittingSize.height, 1)
        let documentHeight = max(contentScroll.contentView.bounds.height, rootHeight + 44)
        scrollDocumentView.setFrameSize(NSSize(width: visibleWidth, height: documentHeight))
        rootStack.frame = NSRect(x: 28, y: documentHeight - rootHeight - 22, width: rootWidth, height: rootHeight)
    }

    private func scrollToTopIfNeeded() {
        guard shouldScrollToTop else { return }
        let top = max(scrollDocumentView.bounds.height - contentScroll.contentView.bounds.height, 0)
        contentScroll.contentView.scroll(to: NSPoint(x: 0, y: top))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        shouldScrollToTop = false
    }

    private func addResultView(_ view: NSView) {
        resultStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: resultStack.widthAnchor).isActive = true
    }

    private func addRecommendationSection(
        title: String,
        detail: String,
        recommendations: [CardRecommendation],
        emptyTitle: String,
        emptyDetail: String
    ) {
        addResultView(panelHeading(title, detail: detail))
        guard let primary = recommendations.first else {
            addResultView(noticeCard(title: emptyTitle, detail: emptyDetail))
            return
        }
        addResultView(recommendationCard(primary, rank: 1, emphasized: true))
    }

    private func recommendationCard(_ recommendation: CardRecommendation, rank: Int, emphasized: Bool) -> NSView {
        let card = panel(containing: NSView(), tone: emphasized ? .emphasized : .standard)

        let content = card.subviews[0]
        let main = NSStackView()
        main.orientation = .vertical
        main.alignment = .width
        main.spacing = emphasized ? 9 : 5
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            main.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])

        let summary = NSStackView()
        summary.orientation = .horizontal
        summary.alignment = .centerY
        summary.spacing = 12
        let rankLabel = NSTextField(labelWithString: "#\(rank)")
        rankLabel.font = .monospacedDigitSystemFont(ofSize: emphasized ? 16 : 13, weight: .bold)
        rankLabel.textColor = emphasized ? .systemIndigo : .secondaryLabelColor
        rankLabel.setContentHuggingPriority(.required, for: .horizontal)
        let nameStack = NSStackView()
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 2
        let name = NSTextField(labelWithString: recommendation.card.name)
        name.font = .systemFont(ofSize: emphasized ? 20 : 15, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        let amount = NSTextField(labelWithString: "今回 \(yen(recommendation.immediateValueYen)) ・ 年換算 \(yen(recommendation.annualNetValueYen))")
        amount.textColor = .secondaryLabelColor
        nameStack.addArrangedSubview(name)
        nameStack.addArrangedSubview(amount)
        nameStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let rateStack = NSStackView()
        rateStack.orientation = .vertical
        rateStack.alignment = .trailing
        let rate = NSTextField(labelWithString: String(format: "%.1f%%", recommendation.effectiveReturnPercent))
        rate.font = .monospacedDigitSystemFont(ofSize: emphasized ? 28 : 18, weight: .bold)
        rate.textColor = emphasized ? .systemIndigo : .labelColor
        let rateCaption = NSTextField(labelWithString: "実質還元")
        rateCaption.font = .systemFont(ofSize: 11)
        rateCaption.textColor = .secondaryLabelColor
        rateStack.addArrangedSubview(rate)
        rateStack.addArrangedSubview(rateCaption)
        rateStack.setContentHuggingPriority(.required, for: .horizontal)
        summary.addArrangedSubview(rankLabel)
        summary.addArrangedSubview(nameStack)
        summary.addArrangedSubview(rateStack)
        main.addArrangedSubview(summary)
        summary.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true

        let benefits = recommendation.appliedBenefits.map(\.title).joined(separator: " / ")
        if !benefits.isEmpty {
            let benefit = NSTextField(wrappingLabelWithString: benefits)
            benefit.font = .systemFont(ofSize: 12, weight: .medium)
            benefit.textColor = .secondaryLabelColor
            main.addArrangedSubview(benefit)
            benefit.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true
        }
        if !recommendation.warnings.isEmpty {
            let warning = NSTextField(wrappingLabelWithString: "要確認: \(recommendation.warnings.joined(separator: "・"))")
            warning.font = .systemFont(ofSize: 11)
            warning.textColor = .systemOrange
            main.addArrangedSubview(warning)
            warning.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true
        }
        return card
    }

    private func noticeCard(title: String, detail: String) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [
            heading,
            detailLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return panel(containing: stack, tone: .subdued)
    }

    private func panelHeading(_ title: String, detail: String) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 16, weight: .bold)
        let description = NSTextField(labelWithString: detail)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, description])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    private func formRow(_ fields: [NSView]) -> NSStackView {
        let row = NSStackView(views: fields)
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private func formField(_ title: String, control: NSView) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [caption, control])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 4
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func panel(containing content: NSView, tone: PanelTone) -> NSView {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = panelBackgroundColor(for: tone).cgColor
        panel.layer?.cornerRadius = 14
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = panelBorderColor(for: tone).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14)
        ])
        return panel
    }

    private func panelBackgroundColor(for tone: PanelTone) -> NSColor {
        switch tone {
        case .standard:
            return NSColor.controlBackgroundColor
        case .emphasized:
            return NSColor.systemIndigo.withAlphaComponent(0.11)
        case .subdued:
            return NSColor.secondarySystemFill
        }
    }

    private func panelBorderColor(for tone: PanelTone) -> NSColor {
        switch tone {
        case .standard:
            return NSColor.separatorColor.withAlphaComponent(0.35)
        case .emphasized:
            return NSColor.systemIndigo.withAlphaComponent(0.45)
        case .subdued:
            return NSColor.separatorColor.withAlphaComponent(0.22)
        }
    }

    private func updateApplicationCandidates(_ candidates: [CardRecommendation]) {
        applicationCandidates = candidates
        applicationPopup.removeAllItems()
        applicationPopup.addItems(withTitles: candidates.map { "\($0.card.name)（今回\(yen($0.immediateValueYen))）" })
        applicationButton.isEnabled = !candidates.isEmpty
    }

    @objc private func openApplicationPage() {
        let index = applicationPopup.indexOfSelectedItem
        guard applicationCandidates.indices.contains(index) else { return }
        NSWorkspace.shared.open(applicationCandidates[index].card.applicationURL)
    }
}

final class HoldingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let model: MacAppModel
    private let table = NSTableView()
    private let searchField = NSSearchField()
    private let pasteButton = NSButton(title: "ペースト", target: nil, action: nil)
    private let searchStatus = NSTextField(labelWithString: "公式確認済みのカードのみ表示します。検索すると関連カードをオンラインの公式サイトから探せます。")
    private let officialSearchButton = NSButton(title: "公式候補リストを表示", target: nil, action: nil)
    private var catalogLookupWorkItem: DispatchWorkItem?
    private var sortKey = "name"
    private var sortAscending = true

    init(model: MacAppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "手持ちカード"
    }

    required init?(coder: NSCoder) { nil }

    private var displayedProducts: [CardProduct] {
        let query = searchQuery
        let filtered = query.isEmpty ? model.products : model.products.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.issuerName.localizedCaseInsensitiveContains(query)
        }
        return filtered.sorted(by: isOrderedBefore)
    }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("held"))
        column.title = "保有"
        column.width = 56
        column.sortDescriptorPrototype = NSSortDescriptor(key: "held", ascending: true)
        table.addTableColumn(column)
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = "カード名"
        name.width = 300
        name.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        table.addTableColumn(name)
        let issuer = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("issuer"))
        issuer.title = "発行会社"
        issuer.width = 300
        issuer.sortDescriptorPrototype = NSSortDescriptor(key: "issuer", ascending: true)
        table.addTableColumn(issuer)
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        table.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: sortAscending)]

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        searchField.placeholderString = "カード名・発行会社を検索"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.target = self
        pasteButton.action = #selector(pasteCardName)
        officialSearchButton.target = self
        officialSearchButton.action = #selector(addFromOfficialSearch)
        officialSearchButton.isEnabled = false
        searchStatus.textColor = .secondaryLabelColor
        searchStatus.lineBreakMode = .byTruncatingTail
        let controls = NSStackView(views: [searchField, pasteButton, officialSearchButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        let container = NSView()
        let stack = NSStackView(views: [controls, searchStatus, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            searchField.widthAnchor.constraint(equalToConstant: 300),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        view = container
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedProducts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, displayedProducts.indices.contains(row) else { return nil }
        let card = displayedProducts[row]
        switch column.identifier.rawValue {
        case "held":
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleHolding(_:)))
            toggle.state = model.isHeld(card.id) ? .on : .off
            toggle.tag = row
            return toggle
        case "name":
            return highlightedTextCell(card.name, matching: searchQuery)
        default:
            return highlightedTextCell(card.issuerName, matching: searchQuery)
        }
    }

    @objc private func toggleHolding(_ sender: NSButton) {
        guard displayedProducts.indices.contains(sender.tag) else { return }
        model.setHeld(sender.state == .on, cardID: displayedProducts[sender.tag].id)
    }

    func reloadData() {
        table.reloadData()
        updateSearchStatus()
    }

    func controlTextDidChange(_ notification: Notification) {
        applySearchChange()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              ["held", "name", "issuer"].contains(key) else {
            return
        }
        sortKey = key
        sortAscending = descriptor.ascending
        table.reloadData()
    }

    @objc private func pasteCardName() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            searchStatus.stringValue = "クリップボードに貼り付けられる文字がありません。"
            return
        }
        searchField.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        applySearchChange()
        view.window?.makeFirstResponder(searchField)
    }

    private func applySearchChange() {
        table.reloadData()
        updateSearchStatus()
        checkPublishedCatalogForMissingCard()
    }

    private func updateSearchStatus() {
        let query = searchQuery
        if query.isEmpty {
            officialSearchButton.isEnabled = false
            searchStatus.stringValue = "公式確認済みのカードのみ表示します。検索すると関連カードをオンラインの公式サイトから探せます。"
        } else if displayedProducts.isEmpty {
            officialSearchButton.isEnabled = true
            searchStatus.stringValue = "「\(query)」は現在のカタログにありません。オンラインの公式サイトから候補を探して追加できます。"
        } else {
            officialSearchButton.isEnabled = true
            searchStatus.stringValue = "\(displayedProducts.count)件。ゴールドなどの関連カードもオンラインの公式サイトから探せます。"
        }
    }

    @objc private func addFromOfficialSearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        officialSearchButton.isEnabled = false
        searchStatus.stringValue = "「\(query)」の公式カード一覧を確認中…"
        model.lookupOfficialCandidates(named: query) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let candidates) where !candidates.isEmpty:
                self.presentOfficialCandidates(candidates)
            case .success:
                self.updateSearchStatus()
                self.searchStatus.stringValue = "「\(query)」に一致する公式商品ページを見つけられませんでした。定期探索でも追加を続けます。"
            case .failure:
                self.updateSearchStatus()
                self.searchStatus.stringValue = "公式ページ候補を取得できませんでした。ネット接続後にもう一度お試しください。"
            }
        }
    }

    private func presentOfficialCandidates(_ candidates: [RemoteCardSearchEntry]) {
        let alert = NSAlert()
        alert.messageText = "公式ページ候補（\(candidates.count)件）"
        alert.informativeText = "発行会社の公式ドメインに一致するページだけを表示しています。下のリストはスクロールでき、検索語に一致する箇所をハイライトしています。"
        let addButton = alert.addButton(withTitle: "保有カードに追加")
        alert.addButton(withTitle: "キャンセル")
        let candidateList = OfficialCandidateListView(candidates: candidates, query: searchQuery)
        addButton.isEnabled = false
        candidateList.selectionDidChange = { isSelected in
            addButton.isEnabled = isSelected
        }
        alert.accessoryView = candidateList
        guard alert.runModal() == .alertFirstButtonReturn else {
            updateSearchStatus()
            return
        }
        guard let candidate = candidateList.selectedCandidate else { return }
        model.addPendingCard(candidate)
        searchField.stringValue = candidate.name
        table.reloadData()
        searchStatus.stringValue = "「\(candidate.name)」を保有カードに追加しました。還元条件は公式データで検証中です。"
        officialSearchButton.isEnabled = false
    }

    private func checkPublishedCatalogForMissingCard() {
        catalogLookupWorkItem?.cancel()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, displayedProducts.isEmpty else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchStatus.stringValue = "「\(query)」をネット上の最新カタログで確認中…"
            self.model.refreshCatalog { [weak self] in
                guard let self else { return }
                self.table.reloadData()
                self.updateSearchStatus()
            }
        }
        catalogLookupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700), execute: workItem)
    }

    private var searchQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isOrderedBefore(_ left: CardProduct, _ right: CardProduct) -> Bool {
        let comparison: ComparisonResult
        switch sortKey {
        case "held":
            let leftHeld = model.isHeld(left.id)
            let rightHeld = model.isHeld(right.id)
            if leftHeld != rightHeld {
                return sortAscending ? !leftHeld : leftHeld
            }
            comparison = left.name.localizedCompare(right.name)
        case "issuer":
            comparison = left.issuerName.localizedCompare(right.issuerName)
        default:
            comparison = left.name.localizedCompare(right.name)
        }
        if comparison == .orderedSame {
            return sortAscending
                ? left.name.localizedCompare(right.name) == .orderedAscending
                : left.name.localizedCompare(right.name) == .orderedDescending
        }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}

private final class OfficialCandidateListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let candidates: [RemoteCardSearchEntry]
    private let query: String
    private let table = NSTableView()
    var selectionDidChange: ((Bool) -> Void)?

    init(candidates: [RemoteCardSearchEntry], query: String) {
        self.candidates = candidates
        self.query = query
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 320))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("candidate"))
        column.width = 600
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 29
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self
        table.dataSource = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    var selectedCandidate: RemoteCardSearchEntry? {
        candidates.indices.contains(table.selectedRow) ? candidates[table.selectedRow] : nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { candidates.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard candidates.indices.contains(row) else { return nil }
        let candidate = candidates[row]
        let source = candidate.discovery ?? "定期探索"
        return highlightedTextCell("[\(source)] \(candidate.name)（\(candidate.issuerName)）", matching: query)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionDidChange?(selectedCandidate != nil)
    }
}

final class CatalogViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: MacAppModel
    private let table = NSTableView()
    private let detail = NSTextView()
    private var sortKey = "name"
    private var sortAscending = true

    init(model: MacAppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "カード一覧"
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        for (identifier, title, width) in [("name", "カード名", 330.0), ("fee", "年会費", 110.0), ("issuer", "発行会社", 280.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
            table.addTableColumn(column)
        }
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        table.target = self
        table.doubleAction = #selector(openOfficialPage)
        table.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: sortAscending)]

        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        let detailScroll = NSScrollView()
        detail.isEditable = false
        detail.font = .systemFont(ofSize: 12)
        detailScroll.documentView = detail
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .bezelBorder
        let split = NSSplitView()
        split.isVertical = false
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(detailScroll)
        view = split
    }

    private var displayedProducts: [CardProduct] {
        model.products.sorted(by: isOrderedBefore)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedProducts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, displayedProducts.indices.contains(row) else { return nil }
        let card = displayedProducts[row]
        switch column.identifier.rawValue {
        case "name": return textCell(card.name)
        case "fee": return textCell(card.annualFeeYen == 0 ? "無料" : yen(card.annualFeeYen))
        default: return textCell(card.issuerName)
        }
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              ["name", "fee", "issuer"].contains(key) else {
            return
        }
        sortKey = key
        sortAscending = descriptor.ascending
        table.reloadData()
        detail.string = ""
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard displayedProducts.indices.contains(table.selectedRow) else { return }
        let card = displayedProducts[table.selectedRow]
        detail.string = "\(card.name)\n\n年会費: \(card.annualFeeYen == 0 ? "無料" : yen(card.annualFeeYen))\n国際ブランド: \(card.networks.map(\.rawValue).joined(separator: " / "))\n\n" + card.benefitRules.map { "• \($0.title)" }.joined(separator: "\n") + "\n\n公式: \(card.applicationURL.absoluteString)"
    }

    @objc private func openOfficialPage() {
        guard displayedProducts.indices.contains(table.selectedRow) else { return }
        NSWorkspace.shared.open(displayedProducts[table.selectedRow].applicationURL)
    }

    func reloadData() {
        table.reloadData()
        detail.string = ""
    }

    private func isOrderedBefore(_ left: CardProduct, _ right: CardProduct) -> Bool {
        let comparison: ComparisonResult
        switch sortKey {
        case "fee":
            if left.annualFeeYen != right.annualFeeYen {
                return sortAscending ? left.annualFeeYen < right.annualFeeYen : left.annualFeeYen > right.annualFeeYen
            }
            comparison = left.name.localizedCompare(right.name)
        case "issuer":
            comparison = left.issuerName.localizedCompare(right.issuerName)
        default:
            comparison = left.name.localizedCompare(right.name)
        }
        if comparison == .orderedSame { return false }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}

final class DataViewController: NSViewController {
    private let model: MacAppModel
    private let refreshAction: () -> Void
    private let changeIconAction: (UseCardIconStyle) -> Void
    private let statusLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let heldLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton(title: "最新カタログを確認", target: nil, action: nil)
    private let iconPicker = NSSegmentedControl(labels: [UseCardIconStyle.standard.label, UseCardIconStyle.night.label], trackingMode: .selectOne, target: nil, action: nil)
    private let standardIconPreview = NSImageView()
    private let nightIconPreview = NSImageView()

    fileprivate init(
        model: MacAppModel,
        iconStyle: UseCardIconStyle,
        refreshAction: @escaping () -> Void,
        changeIconAction: @escaping (UseCardIconStyle) -> Void
    ) {
        self.model = model
        self.refreshAction = refreshAction
        self.changeIconAction = changeIconAction
        super.init(nibName: nil, bundle: nil)
        title = "データ"
        iconPicker.selectedSegment = iconStyle == .night ? 1 : 0
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        iconPicker.target = self
        iconPicker.action = #selector(changeIcon)
        iconPicker.segmentStyle = .rounded
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(countLabel)
        stack.addArrangedSubview(heldLabel)
        stack.addArrangedSubview(refreshButton)
        stack.addArrangedSubview(textCell("保有カードはこのMac内に保存します。カード番号や利用明細は保存しません。"))
        stack.addArrangedSubview(iconSection())
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateLabels()
    }

    @objc private func refresh() {
        setRefreshing(true)
        refreshAction()
    }

    @objc private func changeIcon() {
        let style: UseCardIconStyle = iconPicker.selectedSegment == 1 ? .night : .standard
        changeIconAction(style)
    }

    func setRefreshing(_ refreshing: Bool) {
        refreshButton.isEnabled = !refreshing
        if refreshing { statusLabel.stringValue = "カタログを確認中…" }
        else { updateLabels() }
    }

    private func updateLabels() {
        statusLabel.stringValue = "状態: \(model.catalogStatus)"
        countLabel.stringValue = "カード一覧: \(model.products.count)券種"
        heldLabel.stringValue = "保有カード数: \(model.heldCardIDs.count)枚"
    }

    private func iconSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.addArrangedSubview(titleLabel("アプリアイコン"))

        let previews = NSStackView()
        previews.orientation = .horizontal
        previews.alignment = .top
        previews.spacing = 12
        previews.addArrangedSubview(iconPreview(style: .standard, imageView: standardIconPreview))
        previews.addArrangedSubview(iconPreview(style: .night, imageView: nightIconPreview))
        section.addArrangedSubview(previews)
        section.addArrangedSubview(iconPicker)
        section.addArrangedSubview(textCell("Dockのアイコンをすぐ切り替えます。選択は次回起動後も保持されます。"))
        return section
    }

    private func iconPreview(style: UseCardIconStyle, imageView: NSImageView) -> NSView {
        imageView.image = iconImage(for: style)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 72),
            imageView.heightAnchor.constraint(equalToConstant: 72)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(textCell(style.label))
        return stack
    }

    private func iconImage(for style: UseCardIconStyle) -> NSImage? {
        guard let url = Bundle.main.url(forResource: style.resourceName, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }
}

private func label(_ text: String) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.alignment = .right
    return field
}

private func titleLabel(_ text: String) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .boldSystemFont(ofSize: 16)
    return field
}

private func textCell(_ text: String) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.lineBreakMode = .byTruncatingTail
    return field
}

private func highlightedTextCell(_ text: String, matching query: String) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.lineBreakMode = .byTruncatingTail
    field.attributedStringValue = highlightedText(text, matching: query)
    return field
}

private func highlightedText(_ text: String, matching query: String) -> NSAttributedString {
    let regularFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let result = NSMutableAttributedString(
        string: text,
        attributes: [
            .font: regularFont,
            .foregroundColor: NSColor.labelColor
        ]
    )
    guard !query.isEmpty else { return result }

    let source = text as NSString
    for term in highlightTerms(for: query) {
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let match = source.range(of: term, options: [.caseInsensitive], range: searchRange)
            guard match.location != NSNotFound else { break }
            result.addAttributes([
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.65)
            ], range: match)
            let nextLocation = match.location + match.length
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
    }
    return result
}

private func highlightTerms(for query: String) -> [String] {
    var terms = [query]
    let normalized = query.precomposedStringWithCompatibilityMapping.lowercased()
    if normalized.contains("saison") || query.contains("セゾン") {
        terms.append("SAISON")
        terms.append("セゾン")
    }
    if normalized.contains("view") || query.contains("ビュー") {
        terms.append("VIEW")
        terms.append("ビュー")
    }
    return Array(Set(terms.filter { !$0.isEmpty }))
}

private func yen(_ value: Double) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .currency)
}

private func dateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
