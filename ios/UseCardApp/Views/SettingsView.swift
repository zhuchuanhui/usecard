import SwiftUI

struct SettingsView: View {
    @AppStorage("catalogBaseURL") private var catalogBaseURL = CatalogStore.defaultEndpoint
    let catalogStore: CatalogStore

    private var unavailableSourceCount: Int {
        catalogStore.catalog?.products
            .flatMap(\.sources)
            .filter { $0.freshness != .fresh }
            .count ?? 0
    }

    var body: some View {
        Form {
            Section("カード情報") {
                LabeledContent("データ元", value: catalogStore.source.rawValue)
                LabeledContent("バージョン", value: catalogStore.catalog?.version ?? "未読込")
                LabeledContent("収録カード", value: "\(catalogStore.catalog?.products.count ?? 0)券種")
                LabeledContent("再確認が必要", value: "\(unavailableSourceCount)件")
                if let generatedAt = catalogStore.catalog?.generatedAt {
                    LabeledContent("生成日時", value: generatedAt)
                }
            }

            Section("自動更新") {
                TextField("配信URL", text: $catalogBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await catalogStore.load(endpoint: catalogBaseURL) }
                } label: {
                    Label("今すぐ更新", systemImage: "arrow.clockwise")
                }
                .disabled(catalogStore.isLoading)
            }

            if let warning = catalogStore.warning {
                Section("更新状態") {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("プライバシー") {
                Text("保存するのはカード商品、特典登録状態、利用額の目安だけです。カード番号、名義、セキュリティコード、利用明細は保存しません。")
            }

            Section("注意") {
                Text("このアプリの計算は参考情報です。還元条件、対象外取引、申込条件は利用前に各カード会社の公式サイトで確認してください。")
            }
        }
        .navigationTitle("設定")
    }
}
