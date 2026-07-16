import SwiftUI

struct RootView: View {
    @AppStorage("catalogBaseURL") private var catalogBaseURL = CatalogStore.defaultEndpoint
    @Environment(\.scenePhase) private var scenePhase
    @State private var catalogStore = CatalogStore()

    var body: some View {
        TabView {
            NavigationStack {
                RecommendationView(catalogStore: catalogStore)
            }
            .tabItem { Label("おすすめ", systemImage: "sparkles") }

            NavigationStack {
                HoldingsView(catalogStore: catalogStore)
            }
            .tabItem { Label("手持ち", systemImage: "creditcard") }

            NavigationStack {
                CatalogView(catalogStore: catalogStore)
            }
            .tabItem { Label("カード検索", systemImage: "magnifyingglass") }

            NavigationStack {
                SettingsView(catalogStore: catalogStore)
            }
            .tabItem { Label("設定", systemImage: "gearshape") }
        }
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
