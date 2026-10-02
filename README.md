# UseCard

[English](#english) · [日本語](#日本語) · [简体中文](#简体中文)

---

## English

UseCard tracks the credit cards you own and estimates which one offers the best value based on the amount, merchant, purchase category, payment method, and usage pattern. Card ownership data syncs between your iPhone and Mac through iCloud under the same Apple Account. UseCard does not handle card numbers or transaction histories.

### Features

- Add and remove owned cards; record annual spending, benefits, and point values.
- Rank cards by amount, merchant, category, purchase location, payment method, date, and frequency.
- Separate cards you own from application candidates; browse the full catalog of cards you do not own.
- Compare physical-card payments, contactless card payments, phone contactless payments, Apple Pay, mobile ordering, and QR payments using just a merchant and amount.
- Show non-card payment options (Mobile Suica, nanaco, WAON, PayPay balance, Rakuten Pay balance, d払い, and au PAY balance), with eligibility conditions and official sources listed separately.
- Show estimated rewards, effective reward rates, value after annual fees, and official sources.
- Check official pages every six hours, validate changes, publish catalog versions, and keep the previous version if an update fails.
- Automatically register JCCA member issuers and explore official product-page candidates monthly.
- Use the bundled catalog while offline.

Major merchant- and date-specific rules are calculated when applicable. Current examples include the Rakuten Card bonus at Rakuten Ichiba, SMBC Card (NL) smartphone contactless/mobile-order offers at eligible convenience stores and restaurants, and AEON Card's customer appreciation days on the 20th and 30th. Only card-specific bonuses on top of the regular reward are added; merchant-wide points are excluded so they do not distort card comparisons.

The public catalog includes 36 cards, including JCB Card S, Rakuten Card, Sumitomo Mitsui Card (NL), Olive Flexible Pay Gold, PayPay Card, AEON Card (WAON integrated), EPOS Card, and Orico Card THE POINT (updated 2026-07-17). To expand coverage, UseCard collects official product-page candidates from JCCA-registered issuers and promotes only candidates whose personal application path, annual fee, standard reward rate, point value, and network brand can all be verified on the same official page. Unverified candidates stay in the review queue under `catalog/discovery`.

### Project layout

- `ios/UseCardApp`: iOS app built with SwiftUI, SwiftData, and CloudKit
- `Sources/UseCardCore`: catalog models and on-device recommendation engine
- `services/catalog`: official-page collection, strict extraction, validation, and publishing
- `catalog/public`: app manifest, versioned catalog, official lineup candidates, and payment alternatives
- `catalog/discovery`: issuer/product-page discovery results and promotion reports

### Run the iOS app

Requirements: Xcode, iOS 17 or later, and an Apple Account signed in to iCloud. A free Apple Account is enough for development and device testing. TestFlight or App Store distribution requires the Apple Developer Program (US$99/year or local equivalent).

1. Open `ios/UseCard.xcodeproj` in Xcode.
2. Select a Signing Team for the `UseCard` target. CloudKit and the key-value store are enabled for that team.
3. If you change the Bundle ID or CloudKit container, also update `iCloud.jp.usecard.app` and the shared key-value-store settings in `ios/UseCardApp/UseCard.entitlements`.
4. Run the `UseCard` scheme on an iPhone simulator or a device.

Regenerate the project after changing its project definition:

```sh
./script/generate_xcode_project.sh
```

### Run as a macOS app

On an Apple Silicon Mac running macOS 14 or later, you can build and launch the native `UseCard.app` without Xcode:

```sh
./script/run_macos_app.sh
```

The app is created at `UseCard.app` in the project directory. The macOS app is implemented with Swift and AppKit. Owned cards use the same iCloud key-value store as the iOS app when signed with a compatible identity and Apple Account; without a usable signature, it falls back to local storage on that Mac. The bundled catalog is always available. After publishing GitHub Pages, the app can fetch validated catalog updates at launch and from the Data tab.

### Versioned DMG

Pushing a `v1.2.3` or `1.2.3` Git tag sets the app version to `1.2.3` and attaches `UseCard-1.2.3.dmg` to a GitHub Release. Untagged builds use version `0.0.0`. Build the same artifact locally with:

```sh
APP_VERSION=v1.2.3 ./script/build_macos_dmg.sh
```

In the Owned Cards tab, search the verified catalog by card or issuer name. If there is no match, the app also checks the published online catalog. Choose “Find related cards online” to search using the entered card name and related terms such as “Gold”; only results on JCCA issuer sites or known official card domains are shown. Reward rates and annual fees cannot be entered manually. A selected candidate is added as “under verification” and is excluded from recommendations until its annual fee, standard reward rate, and application path are verified on one official page and it is promoted into a later catalog.

The Recommendations tab lists useful cards you do not own under “Application candidates.” “Open official application page” opens the issuer's official page; it does not fill in or submit an application.

“Compare by merchant and amount” automatically compares payment methods for each card. For example, at 7-Eleven it compares phone contactless, Apple Pay, mobile ordering, and QR payments rather than assuming a physical-card payment. It also lists all non-card payment options. These estimates use only the official reward for paying directly from a balance or stored-value account. They do not add rewards from the card used to top it up, merchant-specific promotions, coupons, or limited-time campaigns. Check eligibility through “Open official rules” for each option.

### Update the catalog

```sh
cd services/catalog
npm ci
npm run typecheck
npm test
npm run update
```

To rediscover issuer product pages and promote candidates that pass the strict checks:

```sh
cd services/catalog
npm run discover -- --crawl
npm run promote
npm run update
```

`update` replaces `catalog/public/latest.json`, `search-index.json`, the official lineup candidates, payment alternatives, and the manifest only after all validation passes. If an official page is unavailable, a value is missing or implausible, or the schema is inconsistent, publishing fails and the previous version on GitHub Pages is retained. Official lineups are configured in `catalog/config/official-card-lineups.json`; recurring payment-alternative rewards are in `catalog/config/payment-alternatives.json`. Lineup aliases can include brands, partners, and membership services—for example, Amazon, アマゾン, Prime, and プライム can find the same official card. For search terms of three or more characters that are absent from the catalog, the app also searches official sites and prioritizes issuer domains. A candidate found only on a partner's official domain can be added as owned, but is not used in recommendations until its reward terms are verified. SMBC official pages currently return 403 in this execution environment, so previously confirmed values remain marked `unavailable` and the app shows a recheck warning.

After publication to GitHub, `.github/workflows/catalog-update.yml` checks and publishes known-card terms every six hours. `.github/workflows/issuer-discovery.yml` searches JCCA issuers monthly and validates and publishes newly discovered cards. The app's default catalog URL is `https://zhuchuanhui.github.io/usecard/`, and it can be changed in Settings.

### Verify

```sh
./script/smoke.sh
```

In a standard Xcode/SwiftPM environment, also run:

```sh
swift test
xcodebuild -project ios/UseCard.xcodeproj -scheme UseCard -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

On this Mac, SwiftPM through Command Line Tools stops before compilation with `Unknown error parsing property list`. The same Swift sources have passed `swiftc` type checking and an executable smoke check. CI runs `swift test` and the iOS build on a macOS runner with Xcode.

### Recommendation assumptions

- Owned cards are compared by the additional rewards from this purchase; already-paid annual fees are not deducted.
- Cards you do not own are annualized using the entered frequency, then annual fees are deducted.
- Sign-up bonuses are not included in standard rewards.
- For stored-value and QR payment options, only rewards for paying directly from the balance are counted. Top-up card rewards and limited-time offers are not double-counted.
- If spending requirements or benefit enrollment are missing, confirmed value and the maximum value when conditions are met are shown separately; ranking uses confirmed value.
- Results are estimates. Review the linked official terms before applying or paying.

---

## 日本語

手持ちのクレジットカードを記録し、金額・店舗・用途・支払い方法などから、一番お得なカードを計算するアプリです。保有情報は同じApple AccountのiPhone・Mac間でiCloudに共有します。カード番号や利用明細は扱いません。

### 主な機能

- 手持ちカードの追加・削除、年間利用額、特典、ポイント価値の記録
- 金額、店舗、用途、購入場所、支払い方法、利用日、頻度によるランキング
- 手持ちカードと申込候補の分離表示。未保有カードの全券種を確認可能
- 店名と金額から、物理カード・カードのタッチ決済・スマホのタッチ決済・Apple Pay・モバイルオーダー・QR決済を自動比較
- カード以外の決済候補（モバイルSuica、nanaco、WAON、PayPay残高、楽天ペイ残高、d払い、au PAY残高）を利用条件・公式根拠とともに表示
- 還元額、実質還元率、年会費控除後の価値、公式根拠の表示
- 公式ページを6時間ごとに監視し、差分を検証して配信。失敗時は前版を維持
- JCCA会員会社の自動登録と、公式商品ページ候補の月次探索
- オフライン時に同梱カタログを利用

店舗・日付による主要ルールも条件に応じて計算します。現在は楽天市場での楽天カード特典分、対象コンビニ・飲食店での三井住友カード（NL）のスマホタッチ／モバイルオーダー利用、イオンカードのお客さま感謝デー（20日・30日）などを収録しています。通常還元にカード固有で上乗せされる分だけを加算し、店舗共通ポイントはカード間比較に含めません。

公開カタログには、JCB カード S、楽天カード、三井住友カード（NL）、Oliveフレキシブルペイ ゴールド、PayPayカード、イオンカード（WAON一体型）、エポスカード、Orico Card THE POINTなど36券種を収録しています（2026-07-17更新）。全券種対応に向け、JCCA登録会社から公式商品ページ候補を集め、個人向け申込導線・年会費・通常還元・ポイント価値・国際ブランドを同じ公式ページで確認できた候補だけを自動昇格します。確認不足の候補は誤掲載せず、`catalog/discovery`の確認待ちキューに残します。

### 構成

- `ios/UseCardApp`: SwiftUI、SwiftData、CloudKitによるiOSアプリ
- `Sources/UseCardCore`: カタログ型と端末内推薦エンジン
- `services/catalog`: 公式ページの収集、厳格な抽出・検証・配信
- `catalog/public`: アプリ配信用manifest、バージョン付きカタログ、公式ラインナップ候補、決済代替手段
- `catalog/discovery`: 発行会社・商品ページの探索結果と昇格レポート

### iOSアプリの起動

必要なものはXcode、iOS 17以上、iCloudにサインインしたApple Accountです。開発・実機テストは無料のApple Accountで始められます。TestFlightまたはApp Storeで配信するにはApple Developer Program（年間99米ドル、現地通貨相当）が必要です。

1. Xcodeで`ios/UseCard.xcodeproj`を開きます。
2. `UseCard`ターゲットでSigning Teamを選択します。このTeamでCloudKitとキーバリューストアが有効になります。
3. Bundle IDまたはCloudKit containerを変更する場合は、`ios/UseCardApp/UseCard.entitlements`の`iCloud.jp.usecard.app`と共有キーバリューストア設定も変更します。
4. iPhoneシミュレータまたは実機で`UseCard`スキームを実行します。

プロジェクト定義を変更した場合は再生成します。

```sh
./script/generate_xcode_project.sh
```

### macOSアプリの起動

XcodeがないMacでも、Apple Silicon・macOS 14以降ならネイティブの`UseCard.app`を作成して起動できます。

```sh
./script/run_macos_app.sh
```

生成先はプロジェクト直下の`UseCard.app`です。macOS版はSwiftとAppKitで実装しています。互換性のある署名とApple Accountで利用すると、iOS版と同じiCloudキーバリューストアに手持ちカードを保存します。有効な署名がない場合はそのMacのローカル保存に切り替わります。同梱カタログは常に利用できます。GitHub Pages公開後は起動時と「データ」タブから検証済みカタログを取得できます。

### バージョン付きDMG

`v1.2.3`または`1.2.3`のGitタグをpushすると、アプリのバージョンを`1.2.3`に設定し、`UseCard-1.2.3.dmg`をGitHub Releaseに添付します。タグなしビルドのバージョンは`0.0.0`です。ローカルでも同じ成果物を作成できます。

```sh
APP_VERSION=v1.2.3 ./script/build_macos_dmg.sh
```

「手持ちカード」タブでは、カード名・発行会社名から公式確認済みカタログを検索します。一致しない場合は公開済みオンラインカタログも確認します。「関連カードをオンラインで探す」では入力したカード名とゴールドなどの関連語で検索し、JCCAの発行会社一覧または既知カードの公式ドメインに一致した結果だけを表示します。還元率や年会費は手入力できません。候補を選ぶと「検証中」として保有カードに追加され、年会費・通常還元・申込導線が同じ公式ページで検証されて後続カタログに昇格するまで、おすすめ計算には使われません。

「おすすめ」タブでは、未保有でお得なカードを「申込候補」に表示します。「公式申込ページを開く」は発行会社の公式ページを開くだけで、申込内容の入力・送信は行いません。

「お店と金額で詳しく調べる」では、カードごとの支払い方法を自動比較します。たとえばセブン‐イレブンなら、物理カード払いに限定せず、スマホのタッチ決済・Apple Pay・モバイルオーダー・QR決済を比較します。結果下部にはカード以外の決済候補もすべて表示します。残高や電子マネーから直接払う場合の公式還元だけを計算し、チャージ元カードの還元、ポイントアップ店、クーポン、期間限定キャンペーンは加算しません。利用条件は各候補の「公式ルールを開く」から確認できます。

### カタログ更新

```sh
cd services/catalog
npm ci
npm run typecheck
npm test
npm run update
```

発行会社の商品ページ候補を再探索し、厳格な条件を満たした候補を昇格する場合：

```sh
cd services/catalog
npm run discover -- --crawl
npm run promote
npm run update
```

`update`は全検証の成功後に限り、`catalog/public/latest.json`、`search-index.json`、公式ラインナップ候補、決済代替手段、manifestを差し替えます。公式ページの取得不能、値の欠落や異常、スキーマ不整合があれば配信を失敗させ、GitHub Pages上の前版を維持します。公式ラインナップは`catalog/config/official-card-lineups.json`、定常的な決済代替手段の還元ルールは`catalog/config/payment-alternatives.json`で管理します。aliasesにはブランド名・提携先・会員サービス名を登録でき、Amazon／アマゾン／Prime／プライムのいずれでも同じ公式カードを検索できます。カタログにない3文字以上の検索語も公式サイトから自動検索し、発行会社の公式ドメインを優先します。提携先の公式ドメインしか見つからない候補は保有登録だけでき、還元条件の検証まではおすすめ計算に使われません。現在この実行環境ではSMBC公式ページが403になるため、確認済み値を`unavailable`状態で保持し、アプリに再確認警告を表示します。

GitHub公開後は`.github/workflows/catalog-update.yml`が6時間ごとに既知カードの条件を検証・配信し、`.github/workflows/issuer-discovery.yml`が毎月JCCA会員会社の公式商品ページを再探索して新規カードを検証・配信します。アプリの初期配信URLは`https://zhuchuanhui.github.io/usecard/`で、設定から変更できます。

### 検証

```sh
./script/smoke.sh
```

通常のXcode／SwiftPM環境では次も実行します。

```sh
swift test
xcodebuild -project ios/UseCard.xcodeproj -scheme UseCard -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

このMacではCommand Line Tools経由のSwiftPMがコンパイル前に`Unknown error parsing property list`で停止します。同じSwiftソースは`swiftc`の型検査と実行スモークテストに成功しています。CIではXcode搭載のmacOS runnerで`swift test`とiOSビルドを実行します。

### 推薦の前提

- 手持ちカードは今回増える還元額で比較し、支払い済みの年会費は差し引きません。
- 未保有カードは入力された頻度で年換算し、年会費を差し引きます。
- 入会キャンペーンは通常還元に含めません。
- 電子マネー・コード決済は残高から直接払う場合の還元だけを計算し、チャージ元カードの還元や期間限定施策を二重計上しません。
- 利用額条件や特典登録が未入力の場合、確定値と条件達成時の最大値を分けて表示し、確定値で順位付けします。
- 結果は参考情報です。利用・申込前に表示された公式リンクで最新条件を確認してください。

---

## 简体中文

UseCard 用于记录您持有的信用卡，并根据金额、商户、用途和支付方式等信息估算最划算的卡。同一 Apple Account 下的 iPhone 和 Mac 通过 iCloud 同步持卡信息。应用不会处理卡号或交易明细。

### 功能

- 添加、删除持有的卡，记录年度消费、权益和积分价值。
- 根据金额、商户、用途、购买地点、支付方式、日期和频率进行排序。
- 将已持有的卡与申请候选卡分开展示，并可查看所有尚未持有的卡。
- 仅输入商户和金额，即可比较实体卡、卡片感应支付、手机感应支付、Apple Pay、手机点单和二维码支付。
- 列出非信用卡支付选项（Mobile Suica、nanaco、WAON、PayPay 余额、Rakuten Pay 余额、d払い、au PAY 余额），并分别显示适用条件和官方依据。
- 显示预估返现、实际返还率、扣除年费后的价值及官方依据。
- 每六小时检查官方页面、验证差异并发布目录版本；更新失败时保留上一版本。
- 自动登记 JCCA 会员发卡机构，并按月搜索官方产品页面候选项。
- 离线时使用内置目录。

符合条件时也会计算主要的商户和日期规则。目前包括乐天市场的乐天卡奖励、三井住友卡（NL）在指定便利店和餐饮店使用手机感应支付／手机点单的奖励，以及 AEON 卡每月 20 日和 30 日的顾客感谢日优惠。只计入信用卡自身叠加在常规奖励之上的部分；商户通用积分不会用于卡片比较。

公开目录收录了 36 款卡，包括 JCB Card S、乐天卡、三井住友卡（NL）、Olive Flexible Pay Gold、PayPay 卡、AEON 卡（集成 WAON）、EPOS 卡和 Orico Card THE POINT（更新于 2026-07-17）。为了逐步覆盖全部卡种，应用会从 JCCA 登记的发卡机构收集官方产品页候选项；只有在同一官方页面上核实个人申请入口、年费、常规奖励率、积分价值和国际卡组织品牌后，才会自动纳入目录。信息尚未核实的候选项会保留在`catalog/discovery`待审核队列中。

### 项目结构

- `ios/UseCardApp`：使用 SwiftUI、SwiftData 和 CloudKit 开发的 iOS 应用
- `Sources/UseCardCore`：目录模型和设备端推荐引擎
- `services/catalog`：官方页面采集、严格提取、验证和发布
- `catalog/public`：应用清单、带版本的目录、官方卡种候选项和支付替代方案
- `catalog/discovery`：发卡机构／产品页搜索结果及晋级报告

### 运行 iOS 应用

需要 Xcode、iOS 17 或更高版本，以及已登录 iCloud 的 Apple Account。个人开发和真机测试可使用免费 Apple Account；通过 TestFlight 或 App Store 发布则需要 Apple Developer Program（每年 99 美元或当地等值费用）。

1. 在 Xcode 中打开`ios/UseCard.xcodeproj`。
2. 为`UseCard` target 选择 Signing Team。CloudKit 和键值存储会在该 Team 下启用。
3. 如果修改 Bundle ID 或 CloudKit 容器，还需同步修改`ios/UseCardApp/UseCard.entitlements`中的`iCloud.jp.usecard.app`及共享键值存储设置。
4. 在 iPhone 模拟器或设备上运行`UseCard` scheme。

修改项目定义后，请重新生成项目：

```sh
./script/generate_xcode_project.sh
```

### 作为 macOS 应用运行

在搭载 Apple Silicon、运行 macOS 14 或更高版本的 Mac 上，即使没有安装 Xcode，也可以创建并运行原生`UseCard.app`：

```sh
./script/run_macos_app.sh
```

应用会生成在项目目录下的`UseCard.app`。macOS 版使用 Swift 和 AppKit 实现。使用兼容的签名和 Apple Account 时，持卡信息会保存到与 iOS 版相同的 iCloud 键值存储；如果没有可用签名，则回退到该 Mac 的本地存储。内置目录始终可用。发布到 GitHub Pages 后，应用可在启动时或“数据”标签页获取已验证的目录更新。

### 带版本号的 DMG

推送`v1.2.3`或`1.2.3`Git 标签时，应用版本会设为`1.2.3`，并将`UseCard-1.2.3.dmg`附加到 GitHub Release。无标签构建的版本为`0.0.0`。也可在本地生成相同的制品：

```sh
APP_VERSION=v1.2.3 ./script/build_macos_dmg.sh
```

在“已持有的卡”标签页中，可按卡名或发卡机构搜索已通过官方核实的目录。没有匹配项时，应用也会检查已发布的在线目录。点击“在线搜索相关卡”后，可使用输入的卡名和 Gold 等相关词搜索；结果仅来自 JCCA 发卡机构列表或已知信用卡的官方域名。不能手动填写奖励率或年费。选中的候选项会以“验证中”状态加入持卡列表，在同一官方页面核实年费、常规奖励率和申请入口并纳入后续目录之前，不会参与推荐计算。

“推荐”标签页会在“申请候选”中列出尚未持有且可能划算的卡。“打开官方申请页面”只会打开发卡机构的官方页面，不会填写或提交申请。

“按商户和金额详细比较”会自动比较每张卡可用的支付方式。例如在 7-Eleven，会比较手机感应支付、Apple Pay、手机点单和二维码支付，而不是只假设使用实体卡。结果下方也会列出所有非信用卡支付选项。估算只计算直接从余额或储值账户支付时的官方奖励，不叠加充值信用卡的奖励、商户加成、优惠券或限时活动。请通过每个选项的“打开官方规则”确认适用条件。

### 更新目录

```sh
cd services/catalog
npm ci
npm run typecheck
npm test
npm run update
```

重新搜索发卡机构产品页，并纳入通过严格检查的候选项：

```sh
cd services/catalog
npm run discover -- --crawl
npm run promote
npm run update
```

只有所有验证都通过后，`update`才会替换`catalog/public/latest.json`、`search-index.json`、官方卡种候选项、支付替代方案和 manifest。若官方页面无法访问、数据缺失或异常，或 schema 不一致，则发布会失败，并保留 GitHub Pages 上的上一版本。官方卡种清单位于`catalog/config/official-card-lineups.json`；常规支付替代奖励规则位于`catalog/config/payment-alternatives.json`。卡种别名可包含品牌、合作方和会员服务名称；例如搜索 Amazon、アマゾン、Prime 或 プライム都能找到同一张官方卡。对于目录中不存在且长度至少为 3 个字符的搜索词，应用也会搜索官方网站，并优先显示发卡机构域名的结果。若只找到合作方官方域名，该候选项可以添加到持卡列表，但在奖励条件核实前不会用于推荐。目前此执行环境访问 SMBC 官方页面会收到 403，因此已核实的数值会保留为`unavailable`状态，应用会提示重新核实。

发布到 GitHub 后，`.github/workflows/catalog-update.yml`每六小时验证并发布已知卡片条件；`.github/workflows/issuer-discovery.yml`每月重新搜索 JCCA 会员机构的官方产品页，并验证、发布新发现的卡片。应用默认目录网址为`https://zhuchuanhui.github.io/usecard/`，可在设置中修改。

### 验证

```sh
./script/smoke.sh
```

在标准 Xcode／SwiftPM 环境中，也可运行：

```sh
swift test
xcodebuild -project ios/UseCard.xcodeproj -scheme UseCard -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

在当前 Mac 上，通过 Command Line Tools 运行的 SwiftPM 会在编译前因`Unknown error parsing property list`停止。同一 Swift 源码已通过`swiftc`类型检查和可执行 smoke 检查。CI 会在装有 Xcode 的 macOS runner 上运行`swift test`和 iOS 构建。

### 推荐计算假设

- 对已持有的卡，仅比较本次消费增加的奖励，不扣除已支付的年费。
- 对尚未持有的卡，根据输入的频率折算成年值后扣除年费。
- 开卡奖励不计入常规奖励。
- 储值和二维码支付只计算直接从余额支付时的奖励，不重复计算充值信用卡奖励或限时优惠。
- 未填写消费条件或权益登记时，会分别显示已确认值和满足条件后的最高值，并按已确认值排序。
- 结果仅供参考。申请或付款前，请通过显示的官方链接确认最新规则。
