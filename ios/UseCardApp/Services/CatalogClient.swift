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
        guard let remoteBaseURL else {
            return CatalogLoadResult(catalog: bundled, source: .bundled, warning: nil)
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
            return CatalogLoadResult(catalog: remote, source: .remote, warning: nil)
        } catch {
            return CatalogLoadResult(
                catalog: bundled,
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
