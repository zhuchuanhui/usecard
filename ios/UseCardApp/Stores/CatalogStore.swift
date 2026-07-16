import Foundation
import Observation
import UseCardCore

@MainActor
@Observable
final class CatalogStore {
    static let defaultEndpoint = "https://zhuchuanhui.github.io/usecard/"

    var catalog: CardCatalog?
    var source: CatalogSource = .bundled
    var warning: String?
    var errorMessage: String?
    var isLoading = false
    var lastLoadedAt: Date?

    private let client = CatalogClient()

    func load(endpoint: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let remoteURL = normalizedURL(endpoint)
        do {
            let result = try await client.load(remoteBaseURL: remoteURL)
            catalog = result.catalog
            source = result.source
            warning = result.warning
            errorMessage = nil
            lastLoadedAt = Date()
        } catch {
            errorMessage = "カード情報を読み込めませんでした"
        }
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }
        if !components.path.hasSuffix("/") { components.path += "/" }
        return components.url
    }
}
