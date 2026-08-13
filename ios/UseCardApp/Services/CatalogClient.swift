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
    let source: CatalogSource
    let warning: String?
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
            return CatalogLoadResult(
                catalog: remote,
                alternativePaymentCatalog: remoteAlternatives,
                source: .remote,
                warning: nil
            )
        } catch {
            return CatalogLoadResult(
                catalog: bundled,
                alternativePaymentCatalog: bundledAlternatives,
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
