import SwiftData
import SwiftUI

@main
struct UseCardApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([HoldingRecord.self])
        do {
            let cloud = ModelConfiguration(
                "UseCard",
                schema: schema,
                cloudKitDatabase: .private("iCloud.jp.usecard.app")
            )
            modelContainer = try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            let local = ModelConfiguration(
                "UseCardLocal",
                schema: schema,
                cloudKitDatabase: .none
            )
            modelContainer = try! ModelContainer(for: schema, configurations: [local])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
