import SwiftUI

struct SettingsView: View {
    @AppStorage("catalogBaseURL") private var catalogBaseURL = CatalogStore.defaultEndpoint
    @AppStorage("appLanguage") private var appLanguage = "system"
    @Environment(\.appLanguage) private var language
    let catalogStore: CatalogStore

    private var unavailableSourceCount: Int {
        catalogStore.catalog?.products
            .flatMap(\.sources)
            .filter { $0.freshness != .fresh }
            .count ?? 0
    }

    var body: some View {
        Form {
            Section {
                Picker(language.text("settings.language"), selection: $appLanguage) {
                    Text(language.text("settings.language.system")).tag("system")
                    Text(language.text("settings.language.japanese")).tag("ja")
                    Text(language.text("settings.language.english")).tag("en")
                    Text(language.text("settings.language.simplifiedChinese")).tag("zh-Hans")
                    Text(language.text("settings.language.traditionalChinese")).tag("zh-Hant")
                }
                .onChange(of: appLanguage) { _, value in
                    let identifier = value == "system" ? "system" : value
                    NotificationCenter.default.post(name: .useCardLanguageChanged, object: identifier)
                }
            }
            Section(language.text("settings.cardInformation")) {
                LabeledContent(language.text("settings.dataSource"), value: language.text(catalogStore.source == .bundled ? "settings.source.bundled" : "settings.source.remote"))
                LabeledContent(language.text("settings.version"), value: catalogStore.catalog?.version ?? language.text("common.notLoaded"))
                LabeledContent(language.text("catalog.includedCards"), value: language.format("settings.cardCountFormat", catalogStore.catalog?.products.count ?? 0))
                LabeledContent(language.text("settings.needsReview"), value: language.format("settings.itemCountFormat", unavailableSourceCount))
                if let generatedAt = catalogStore.catalog?.generatedAt {
                    LabeledContent(language.text("settings.generatedAt"), value: generatedAt)
                }
            }

            Section(language.text("settings.automaticUpdates")) {
                TextField(language.text("settings.catalogURL"), text: $catalogBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await catalogStore.load(endpoint: catalogBaseURL) }
                } label: {
                    Label(language.text("settings.refreshNow"), systemImage: "arrow.clockwise")
                }
                .disabled(catalogStore.isLoading)
            }

            Section(language.text("settings.sync")) {
                Text(language.text("settings.syncDescription"))
                Text(language.text("settings.localOnlyDescription"))
                    .foregroundStyle(.secondary)
            }

            if let warning = catalogStore.warning {
                Section(language.text("settings.updateStatus")) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section(language.text("settings.privacy")) {
                Text(language.text("settings.privacyDescription"))
            }

            Section(language.text("settings.notice")) {
                Text(language.text("settings.noticeDescription"))
            }
        }
        .navigationTitle(language.text("tab.settings"))
        .navigationBarTitleDisplayMode(.large)
    }
}
