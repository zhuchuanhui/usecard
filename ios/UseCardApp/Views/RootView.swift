import SwiftUI

struct RootView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("catalogBaseURL") private var catalogBaseURL = CatalogStore.defaultEndpoint
    @Environment(\.scenePhase) private var scenePhase
    @State private var catalogStore = CatalogStore()

    var body: some View {
        TabView {
            NavigationStack {
                RecommendationView(catalogStore: catalogStore)
            }
            .tabItem { Label(language.text("tab.recommendations"), systemImage: "sparkles") }

            NavigationStack {
                HoldingsView(catalogStore: catalogStore)
            }
            .tabItem { Label(language.text("tab.holdings"), systemImage: "creditcard") }

            NavigationStack {
                CatalogView(catalogStore: catalogStore)
            }
            .tabItem { Label(language.text("tab.catalog"), systemImage: "magnifyingglass") }

            NavigationStack {
                SettingsView(catalogStore: catalogStore)
            }
            .tabItem { Label(language.text("tab.settings"), systemImage: "gearshape") }
        }
        .background(SharedHoldingsBootstrap())
        .task {
            await catalogStore.load(endpoint: catalogBaseURL)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  let lastLoadedAt = catalogStore.lastLoadedAt,
                  Date().timeIntervalSince(lastLoadedAt) > 6 * 60 * 60 else { return }
            Task { await catalogStore.load(endpoint: catalogBaseURL) }
        }
    }
}
