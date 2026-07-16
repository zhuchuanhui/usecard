import XCTest
import UseCardCore

final class CatalogDecodingTests: XCTestCase {
    func testBundledCatalogDecodes() throws {
        let bundle = Bundle(for: Self.self)
        let appBundle = Bundle(identifier: "jp.usecard.app") ?? bundle
        guard let url = appBundle.url(forResource: "latest", withExtension: "json") else {
            throw XCTSkip("Bundled catalog is available in the app target build")
        }
        let catalog = try JSONDecoder().decode(CardCatalog.self, from: Data(contentsOf: url))
        XCTAssertFalse(catalog.products.isEmpty)
        XCTAssertEqual(catalog.schemaVersion, 1)
    }
}
