import CryptoKit
import Foundation
import UseCardCore

struct CatalogManifest: Decodable {
    let schemaVersion: Int
    let catalogVersion: String
    let generatedAt: String
    let path: String
    let sha256: String
    let productCount: Int
}

struct CatalogLoadResult {
    let catalog: CardCatalog
    let alternativePaymentCatalog: AlternativePaymentCatalog
    let onlineCandidates: [OnlineCardCandidate]
    let source: CatalogSource
    let warning: String?
}

struct OnlineCardCandidate: Codable, Hashable, Identifiable {
    let issuerID: String
    let issuerName: String
    let name: String
    let officialURL: URL
    let observedAt: String
    let aliases: [String]

    var id: String { officialURL.absoluteString }

    init(
        issuerID: String,
        issuerName: String,
        name: String,
        officialURL: URL,
        observedAt: String,
        aliases: [String] = []
    ) {
        self.issuerID = issuerID
        self.issuerName = issuerName
        self.name = name
        self.officialURL = officialURL
        self.observedAt = observedAt
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey {
        case issuerID
        case issuerName
        case name
        case officialURL
        case observedAt
        case aliases
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            issuerID: try values.decode(String.self, forKey: .issuerID),
            issuerName: try values.decode(String.self, forKey: .issuerName),
            name: try values.decode(String.self, forKey: .name),
            officialURL: try values.decode(URL.self, forKey: .officialURL),
            observedAt: try values.decode(String.self, forKey: .observedAt),
            aliases: try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
        )
    }
}

private struct OfficialLineup: Decodable {
    let issuerID: String
    let issuerName: String
    let aliases: [String]
    let observedAt: String
    let cards: [OfficialLineupCard]
}

private struct OfficialLineupCard: Decodable {
    let name: String
    let officialURL: URL
}

enum CatalogSource: String {
    case bundled = "同梱データ"
    case remote = "自動更新データ"
}

actor CatalogClient {
    private let decoder = JSONDecoder()

    func load(remoteBaseURL: URL?) async throws -> CatalogLoadResult {
        let bundled = try loadBundledCatalog()
        let bundledAlternatives = try loadBundledAlternativePayments()
        guard let remoteBaseURL else {
            return CatalogLoadResult(
                catalog: bundled,
                alternativePaymentCatalog: bundledAlternatives,
                onlineCandidates: loadBundledOnlineCandidates(),
                source: .bundled,
                warning: nil
            )
        }

        do {
            let manifestURL = remoteBaseURL.appending(path: "manifest.json")
            let (manifestData, manifestResponse) = try await URLSession.shared.data(from: manifestURL)
            try requireSuccess(manifestResponse)
            let manifest = try decoder.decode(CatalogManifest.self, from: manifestData)
            guard manifest.schemaVersion == 1 else { throw CatalogClientError.unsupportedSchema }

            let catalogURL = remoteBaseURL.appending(path: manifest.path)
            let (catalogData, catalogResponse) = try await URLSession.shared.data(from: catalogURL)
            try requireSuccess(catalogResponse)
            guard sha256(catalogData) == manifest.sha256 else { throw CatalogClientError.checksumMismatch }
            let remote = try decoder.decode(CardCatalog.self, from: catalogData)
            guard remote.schemaVersion == 1, remote.version == manifest.catalogVersion else {
                throw CatalogClientError.manifestMismatch
            }
            let remoteAlternatives = try await loadAlternativePayments(
                from: remoteBaseURL,
                fallback: bundledAlternatives
            )
            let remoteCandidates = await loadOnlineCandidates(
                from: remoteBaseURL,
                fallback: loadBundledOnlineCandidates()
            )
            return CatalogLoadResult(
                catalog: remote,
                alternativePaymentCatalog: remoteAlternatives,
                onlineCandidates: remoteCandidates,
                source: .remote,
                warning: nil
            )
        } catch {
            return CatalogLoadResult(
                catalog: bundled,
                alternativePaymentCatalog: bundledAlternatives,
                onlineCandidates: loadBundledOnlineCandidates(),
                source: .bundled,
                warning: "更新データを取得できないため、同梱版を使用しています"
            )
        }
    }

    private func loadBundledCatalog() throws -> CardCatalog {
        guard let url = Bundle.main.url(forResource: "latest", withExtension: "json") else {
            throw CatalogClientError.missingBundledCatalog
        }
        return try decoder.decode(CardCatalog.self, from: Data(contentsOf: url))
    }

    private func loadBundledAlternativePayments() throws -> AlternativePaymentCatalog {
        guard let url = Bundle.main.url(forResource: "payment-alternatives", withExtension: "json") else {
            throw CatalogClientError.missingBundledCatalog
        }
        let catalog = try decoder.decode(AlternativePaymentCatalog.self, from: Data(contentsOf: url))
        guard catalog.schemaVersion == 1 else { throw CatalogClientError.unsupportedSchema }
        return catalog
    }

    private func loadBundledOnlineCandidates() -> [OnlineCardCandidate] {
        guard let searchURL = Bundle.main.url(forResource: "search-index", withExtension: "json"),
              let searchData = try? Data(contentsOf: searchURL),
              let searchCandidates = try? decoder.decode([OnlineCardCandidate].self, from: searchData) else {
            return []
        }
        let lineupURL = Bundle.main.url(forResource: "official-lineups", withExtension: "json")
        let lineups = lineupURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? decoder.decode([OfficialLineup].self, from: $0) } ?? []
        return mergeCandidates(searchCandidates, with: lineups)
    }

    private func loadOnlineCandidates(
        from baseURL: URL,
        fallback: [OnlineCardCandidate]
    ) async -> [OnlineCardCandidate] {
        async let searchData = fetchData(from: baseURL.appending(path: "search-index.json"))
        async let lineupData = fetchData(from: baseURL.appending(path: "official-lineups.json"))
        guard let searchData = await searchData,
              let searchCandidates = try? decoder.decode([OnlineCardCandidate].self, from: searchData) else {
            return fallback
        }
        let lineups = await lineupData
            .flatMap { try? decoder.decode([OfficialLineup].self, from: $0) } ?? []
        return mergeCandidates(searchCandidates, with: lineups)
    }

    private func fetchData(from url: URL) async -> Data? {
        guard let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            return nil
        }
        return result.0
    }

    private func mergeCandidates(
        _ searchCandidates: [OnlineCardCandidate],
        with lineups: [OfficialLineup]
    ) -> [OnlineCardCandidate] {
        var byURL = Dictionary(uniqueKeysWithValues: searchCandidates.map { ($0.officialURL.absoluteString, $0) })
        for lineup in lineups {
            for card in lineup.cards {
                let key = card.officialURL.absoluteString
                if let existing = byURL[key] {
                    byURL[key] = OnlineCardCandidate(
                        issuerID: existing.issuerID,
                        issuerName: existing.issuerName,
                        name: existing.name,
                        officialURL: existing.officialURL,
                        observedAt: existing.observedAt,
                        aliases: Array(Set(existing.aliases + lineup.aliases)).sorted()
                    )
                } else {
                    byURL[key] = OnlineCardCandidate(
                        issuerID: lineup.issuerID,
                        issuerName: lineup.issuerName,
                        name: card.name,
                        officialURL: card.officialURL,
                        observedAt: lineup.observedAt,
                        aliases: lineup.aliases
                    )
                }
            }
        }
        return byURL.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func loadAlternativePayments(
        from baseURL: URL,
        fallback: AlternativePaymentCatalog
    ) async throws -> AlternativePaymentCatalog {
        do {
            let url = baseURL.appending(path: "payment-alternatives.json")
            let (data, response) = try await URLSession.shared.data(from: url)
            try requireSuccess(response)
            let catalog = try decoder.decode(AlternativePaymentCatalog.self, from: data)
            guard catalog.schemaVersion == 1 else { throw CatalogClientError.unsupportedSchema }
            return catalog
        } catch {
            return fallback
        }
    }

    private func requireSuccess(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw CatalogClientError.badResponse
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum CatalogClientError: Error {
    case missingBundledCatalog
    case badResponse
    case unsupportedSchema
    case checksumMismatch
    case manifestMismatch
}
