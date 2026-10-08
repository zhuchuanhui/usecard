import SwiftData
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, japanese = "ja", english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var localeIdentifier: String {
        if self != .system { return rawValue }
        let preferred = Locale.preferredLanguages
        for language in preferred {
            if language.hasPrefix("zh-Hant") || language == "zh-TW" || language == "zh-HK" { return "zh-Hant" }
            if language.hasPrefix("zh") { return "zh-Hans" }
            if language.hasPrefix("ja") { return "ja" }
            if language.hasPrefix("en") { return "en" }
        }
        return "ja"
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

@main
struct UseCardApp: App {
    private let modelContainer: ModelContainer
    @State private var languageIdentifier = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"

    private var language: AppLanguage { AppLanguage(rawValue: languageIdentifier) ?? .system }

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
                .environment(\.locale, language.locale)
                .environment(\.appLanguage, language)
                .onReceive(NotificationCenter.default.publisher(for: .useCardLanguageChanged)) { notification in
                    if let identifier = notification.object as? String { languageIdentifier = identifier }
                }
        }
        .modelContainer(modelContainer)
    }
}

extension Notification.Name {
    static let useCardLanguageChanged = Notification.Name("useCardLanguageChanged")
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.system
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
