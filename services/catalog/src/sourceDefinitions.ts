import type { CardNetwork, CardProduct, BenefitRule, SourceEvidence } from "./schema.js";
import { emptyConditions } from "./schema.js";
import type { FetchedPage } from "./fetching.js";

export interface KnownCardDefinition {
  id: string;
  issuerID: string;
  issuerName: string;
  name: string;
  networks: CardNetwork[];
  applicationURL: string;
  eligibilityNote: string;
  pointProgramID: string;
  sourceURLs: string[];
  fallbackTexts?: Record<string, string>;
  build(pages: FetchedPage[], sources: SourceEvidence[]): CardProduct;
}

function findPoints(text: string, patterns: RegExp[]): { unit: number; points: number } {
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    if (match?.[1] && match[2]) {
      return {
        unit: Number(match[1].replaceAll(",", "")),
        points: Number(match[2].replaceAll(",", ""))
      };
    }
  }
  throw new Error("Could not extract base point unit from official page");
}

function assertAnyText(pages: FetchedPage[], patterns: RegExp[], label: string): void {
  const combined = pages.map((page) => page.text).join(" ");
  if (!patterns.some((pattern) => pattern.test(combined))) {
    throw new Error(`Could not verify ${label} on official page`);
  }
}

function pointsRule(
  id: string,
  title: string,
  programID: string,
  unit: number,
  points: number,
  source: SourceEvidence,
  conditions = emptyConditions(),
  stackingGroup = "base",
  defaultPointValueYen = 1
): BenefitRule {
  return {
    id,
    title,
    stackingGroup,
    conditions,
    reward: {
      kind: "pointsPerUnit",
      unitAmountYen: unit,
      pointsPerUnit: points,
      pointProgramID: programID,
      defaultPointValueYen
    },
    source
  };
}

function freePointsCard(
  definition: Omit<KnownCardDefinition, "build">,
  pointPatterns: RegExp[],
  extraRules: (sources: SourceEvidence[]) => BenefitRule[] = () => [],
  includeExtractedBase = true
): KnownCardDefinition {
  return {
    ...definition,
    build(pages, sources) {
      assertAnyText(
        pages,
        [/年会費.{0,500}(永年)?無料/, /年会費\s*無料/],
        `${definition.id} free annual fee`
      );
      const { unit, points } = findPoints(pages.map((page) => page.text).join(" "), pointPatterns);
      const source = sources[0];
      if (!source) throw new Error(`Missing source for ${definition.id}`);
      return {
        id: definition.id,
        issuerID: definition.issuerID,
        issuerName: definition.issuerName,
        name: definition.name,
        networks: definition.networks,
        annualFeeYen: 0,
        applicationStatus: "open",
        applicationURL: definition.applicationURL,
        eligibilityNote: definition.eligibilityNote,
        pointProgramID: definition.pointProgramID,
        benefitRules: [
          ...(includeExtractedBase ? [pointsRule(
            `${definition.id}-base`,
            "通常還元",
            definition.pointProgramID,
            unit,
            points,
            source
          )] : []),
          ...extraRules(sources)
        ],
        sources
      };
    }
  };
}

export const knownCardDefinitions: KnownCardDefinition[] = [
  freePointsCard(
    {
      id: "jcb-card-s",
      issuerID: "jcb",
      issuerName: "株式会社ジェーシービー",
      name: "JCB カード S",
      networks: ["jcb"],
      applicationURL: "https://www.jcb.co.jp/ordercard/kojin_card/os_card_s.html",
      eligibilityNote: "日本国内在住で本人または配偶者に安定継続収入のある18歳以上、または高校生を除く18歳以上の学生",
      pointProgramID: "j-point",
      sourceURLs: ["https://www.jcb.co.jp/ordercard/kojin_card/os_card_s.html"]
    },
    [/([0-9,]+)円(?:\(税込\))?につき([0-9,]+)ポイント/]
  ),
  freePointsCard(
    {
      id: "rakuten-card",
      issuerID: "rakuten-card",
      issuerName: "楽天カード株式会社",
      name: "楽天カード",
      networks: ["visa", "mastercard", "jcb", "americanExpress"],
      applicationURL: "https://www.rakuten-card.co.jp/card/rakuten-card/",
      eligibilityNote: "18歳以上（高校生を除く）",
      pointProgramID: "rakuten-point",
      sourceURLs: ["https://www.rakuten-card.co.jp/card/rakuten-card/"]
    },
    [/(?:カード利用額|ご利用額)?\s*([0-9,]+)円(?:\(税込\))?につき([0-9,]+)ポイント/, /([0-9,]+)円で([0-9,]+)ポイント/],
    (sources) => [
      pointsRule(
        "rakuten-card-rakuten-market-bonus",
        "楽天市場の楽天カード特典分（通常還元に追加）",
        "rakuten-point",
        100,
        1,
        requiredSource(sources, 0, "rakuten-card"),
        { ...emptyConditions(), merchantIDs: ["rakuten-market"], channels: ["online"] },
        "rakuten-market-card-bonus"
      )
    ]
  ),
  {
    id: "smbc-card-gold-nl",
    issuerID: "smbc-card",
    issuerName: "三井住友カード株式会社",
    name: "三井住友カード ゴールド（NL）",
    networks: ["visa", "mastercard"],
    applicationURL: "https://www.smbc-card.com/nyukai/card/gold-numberless.jsp",
    eligibilityNote: "満20歳以上で本人に安定継続収入のある方",
    pointProgramID: "v-point",
    sourceURLs: [
      "https://www.smbc-card.com/nyukai/card/gold-numberless.jsp",
      "https://www.smbc-card.com/nyukai/merit/proper_p5.jsp"
    ],
    fallbackTexts: {
      "https://www.smbc-card.com/nyukai/card/gold-numberless.jsp": "三井住友カード ゴールド（NL） 年会費 5,500円 Vポイント 通常 ご利用金額200円(税込)につき1ポイント 国際ブランド Visa Mastercard 年間100万円のご利用で翌年以降の年会費永年無料",
      "https://www.smbc-card.com/nyukai/merit/proper_p5.jsp": "対象のコンビニ・飲食店で、スマホのVisaのタッチ決済・Mastercardタッチ決済またはモバイルオーダーで支払うと、ご利用金額200円(税込)につき7%ポイント還元。通常のポイント分0.5%に加えて+6.5%ポイント還元。セブン-イレブン ローソン マクドナルド モスバーガー ケンタッキーフライドチキン 吉野家 サイゼリヤ ガスト すき家 はま寿司 ドトールコーヒーショップ"
    },
    build(pages, sources) {
      assertAnyText(pages, [/200円.{0,40}1ポイント/, /200円.{0,40}7%ポイント還元/], "smbc-card-gold-nl rewards");
      const baseSource = requiredSource(sources, 0, "smbc-card-gold-nl");
      return {
        id: "smbc-card-gold-nl",
        issuerID: "smbc-card",
        issuerName: "三井住友カード株式会社",
        name: "三井住友カード ゴールド（NL）",
        networks: ["visa", "mastercard"],
        annualFeeYen: 5_500,
        applicationStatus: "open",
        applicationURL: "https://www.smbc-card.com/nyukai/card/gold-numberless.jsp",
        eligibilityNote: "満20歳以上で本人に安定継続収入のある方。年間100万円利用で翌年以降の年会費が永年無料となる条件は公式ページで確認してください。",
        pointProgramID: "v-point",
        benefitRules: [
          pointsRule("smbc-card-gold-nl-base", "通常還元", "v-point", 200, 1, baseSource),
          pointsRule(
            "smbc-card-gold-nl-eligible-store-mobile-payment",
            "対象コンビニ・飲食店でスマホのタッチ決済／モバイルオーダー（通常還元に追加）",
            "v-point",
            200,
            13,
            requiredSource(sources, 1, "smbc-card-gold-nl eligible stores"),
            {
              ...emptyConditions(),
              merchantIDs: [
                "seicomart", "seven-eleven", "poplar", "ministop", "lawson",
                "mcdonalds", "mos-burger", "kfc", "yoshinoya", "saizeriya",
                "gusto", "bamiya", "syabuyo", "jonathan", "yumean", "sukiya",
                "hamazushi", "cocos", "doutor", "excelsior", "kappazushi"
              ],
              paymentMethods: ["mobileContactless", "applePay", "mobileOrder"]
            },
            "smbc-eligible-store-mobile-payment-bonus"
          )
        ],
        sources
      };
    }
  },
  {
    id: "olive-flexible-pay-gold",
    issuerID: "smbc-card",
    issuerName: "三井住友カード株式会社",
    name: "Oliveフレキシブルペイ ゴールド",
    networks: ["visa"],
    applicationURL: "https://www.smbc-card.com/olive_flexible_pay/card/index.jsp",
    eligibilityNote: "日本国内在住の満20歳以上で本人に安定継続収入のある方（クレジットモード）",
    pointProgramID: "v-point",
    sourceURLs: [
      "https://www.smbc-card.com/olive_flexible_pay/card/index.jsp",
      "https://faq-nyukai.smbc-card.com/--69969b97f2e8a6717b2ae9d4"
    ],
    fallbackTexts: {
      "https://www.smbc-card.com/olive_flexible_pay/card/index.jsp": "Oliveフレキシブルペイ ゴールド 年会費 5,500円 Vポイント 通常 ご利用金額200円(税込)につき1ポイント Visa 年間100万円のご利用で翌年度以降の年会費永年無料 クレジットモード 満20歳以上 安定継続収入",
      "https://faq-nyukai.smbc-card.com/--69969b97f2e8a6717b2ae9d4": "Oliveフレキシブルペイ 一般・ゴールドについて、クレジットモードでは8%ポイント還元、デビットモードでは1.5%ポイント還元。対象のコンビニ・飲食店で、スマホのVisaのタッチ決済・Mastercardタッチ決済またはモバイルオーダーで支払うと、ご利用金額200円(税込)につき8%ポイント還元"
    },
    build(pages, sources) {
      assertAnyText(pages, [/200円.{0,40}1ポイント/, /200円.{0,40}8%ポイント還元/], "olive-flexible-pay-gold rewards");
      const baseSource = requiredSource(sources, 0, "olive-flexible-pay-gold");
      return {
        id: "olive-flexible-pay-gold",
        issuerID: "smbc-card",
        issuerName: "三井住友カード株式会社",
        name: "Oliveフレキシブルペイ ゴールド",
        networks: ["visa"],
        annualFeeYen: 5_500,
        applicationStatus: "open",
        applicationURL: "https://www.smbc-card.com/olive_flexible_pay/card/index.jsp",
        eligibilityNote: "日本国内在住の満20歳以上で本人に安定継続収入のある方（クレジットモード）。年間100万円利用で翌年度以降の年会費が永年無料となる条件は公式ページで確認してください。",
        pointProgramID: "v-point",
        benefitRules: [
          pointsRule("olive-flexible-pay-gold-base", "通常還元", "v-point", 200, 1, baseSource),
          pointsRule(
            "olive-flexible-pay-gold-eligible-store-mobile-payment",
            "対象コンビニ・飲食店でスマホのタッチ決済／モバイルオーダー（クレジットモード・通常還元に追加）",
            "v-point",
            200,
            15,
            requiredSource(sources, 1, "olive-flexible-pay-gold eligible stores"),
            {
              ...emptyConditions(),
              merchantIDs: [
                "seicomart", "seven-eleven", "poplar", "ministop", "lawson",
                "mcdonalds", "mos-burger", "kfc", "yoshinoya", "saizeriya",
                "gusto", "bamiya", "syabuyo", "jonathan", "yumean", "sukiya",
                "hamazushi", "cocos", "doutor", "excelsior", "kappazushi"
              ],
              paymentMethods: ["mobileContactless", "applePay", "mobileOrder"],
              activeFrom: "2026-02-01"
            },
            "olive-flexible-pay-gold-eligible-store-mobile-payment-bonus"
          )
        ],
        sources
      };
    }
  },
  {
    id: "saison-gold-premium",
    issuerID: "credit-saison",
    issuerName: "株式会社クレディセゾン",
    name: "SAISON GOLD Premium",
    networks: ["visa", "jcb", "americanExpress"],
    applicationURL: "https://www.saisoncard.co.jp/creditcard/lineup/102/",
    eligibilityNote: "申込条件は公式サイトで確認してください",
    pointProgramID: "permanent-point",
    sourceURLs: ["https://www.saisoncard.co.jp/creditcard/lineup/102/"],
    fallbackTexts: {
      "https://www.saisoncard.co.jp/creditcard/lineup/102/": "SAISON GOLD Premium 年会費 11,000円 身近なお店で最大5%ポイント還元 年間利用額30万円以下でポイント還元率2.5% マクドナルド モスバーガー すき家"
    },
    build(pages, sources) {
      assertAnyText(pages, [/ポイントアップショップ/, /ポイント還元率2\.5%/], "saison-gold-premium rewards");
      const source = requiredSource(sources, 0, "saison-gold-premium");
      return {
        id: "saison-gold-premium",
        issuerID: "credit-saison",
        issuerName: "株式会社クレディセゾン",
        name: "SAISON GOLD Premium",
        networks: ["visa", "jcb", "americanExpress"],
        annualFeeYen: 11_000,
        applicationStatus: "open",
        applicationURL: "https://www.saisoncard.co.jp/creditcard/lineup/102/",
        eligibilityNote: "ポイントアップショップの還元率は年間利用額により変動します。最新のレベルはセゾンPortalで確認してください。",
        pointProgramID: "permanent-point",
        benefitRules: [
          cashbackRule("saison-gold-premium-base", "通常還元（永久不滅ポイントを1ポイント5円相当で利用する場合）", 0.5, source),
          cashbackRule(
            "saison-gold-premium-point-up-shops",
            "ポイントアップショップ（通常還元に追加・基本レベル）",
            2,
            source,
            { ...emptyConditions(), merchantIDs: ["mcdonalds", "mos-burger", "sukiya"] },
            "saison-gold-premium-point-up-shops"
          )
        ],
        sources
      };
    }
  },
  {
    id: "mizuho-mileage-club-card-saison",
    issuerID: "credit-saison",
    issuerName: "株式会社クレディセゾン",
    name: "みずほマイレージクラブカードセゾン",
    networks: ["visa", "jcb", "americanExpress"],
    applicationURL: "https://www.saisoncard.co.jp/creditcard/lineup/064/",
    eligibilityNote: "申込条件は公式サイトで確認してください",
    pointProgramID: "permanent-point",
    sourceURLs: ["https://www.saisoncard.co.jp/creditcard/lineup/064/"],
    fallbackTexts: {
      "https://www.saisoncard.co.jp/creditcard/lineup/064/": "みずほマイレージクラブカードセゾン 年会費無料 永久不滅ポイント 1ヵ月のショッピングご利用総額1,000円(税込)ごとに1ポイント パートナー企業で永久不滅ポイント通常の2倍"
    },
    build(pages, sources) {
      assertAnyText(pages, [/1,000円.{0,40}1ポイント/, /永久不滅ポイント/], "mizuho-mileage-club-card-saison rewards");
      const source = requiredSource(sources, 0, "mizuho-mileage-club-card-saison");
      return {
        id: "mizuho-mileage-club-card-saison",
        issuerID: "credit-saison",
        issuerName: "株式会社クレディセゾン",
        name: "みずほマイレージクラブカードセゾン",
        networks: ["visa", "jcb", "americanExpress"],
        annualFeeYen: 0,
        applicationStatus: "open",
        applicationURL: "https://www.saisoncard.co.jp/creditcard/lineup/064/",
        eligibilityNote: "永久不滅ポイントを1ポイント5円相当で利用する場合の比較です。パートナー企業での上乗せ条件は公式ページで確認してください。",
        pointProgramID: "permanent-point",
        benefitRules: [
          pointsRule(
            "mizuho-mileage-club-card-saison-base",
            "通常還元（永久不滅ポイントを1ポイント5円相当で利用する場合）",
            "permanent-point",
            1_000,
            1,
            source,
            emptyConditions(),
            "base",
            5
          )
        ],
        sources
      };
    }
  },
  freePointsCard(
    {
      id: "smbc-card-nl",
      issuerID: "smbc-card",
      issuerName: "三井住友カード株式会社",
      name: "三井住友カード（NL）",
      networks: ["visa", "mastercard"],
      applicationURL: "https://www.smbc-card.com/nyukai/card/numberless.jsp",
      eligibilityNote: "満18歳以上（高校生を除く）",
      pointProgramID: "v-point",
      sourceURLs: [
        "https://www.smbc-card.com/nyukai/card/numberless.jsp",
        "https://www.smbc-card.com/nyukai/merit/proper_p5.jsp"
      ],
      fallbackTexts: {
        "https://www.smbc-card.com/nyukai/card/numberless.jsp": "三井住友カード ナンバーレス(NL) 年会費 永年無料 ポイントサービス Vポイント 通常 ご利用金額200円(税込)につき1ポイント 国際ブランド Visa Mastercard",
        "https://www.smbc-card.com/nyukai/merit/proper_p5.jsp": "対象のコンビニ・飲食店で、スマホのVisaのタッチ決済・Mastercardタッチ決済またはモバイルオーダーで支払うと、ご利用金額200円(税込)につき7%ポイント還元。通常のポイント分0.5%に加えて+6.5%ポイント還元。セブン-イレブン ローソン マクドナルド モスバーガー ケンタッキーフライドチキン 吉野家 サイゼリヤ ガスト すき家 はま寿司 ドトールコーヒーショップ"
      }
    },
    [/ご利用金額([0-9,]+)円(?:\(税込\))?につき([0-9,]+)ポイント/],
    (sources) => [
      pointsRule(
        "smbc-card-nl-eligible-store-mobile-payment",
        "対象コンビニ・飲食店でスマホのタッチ決済／モバイルオーダー（通常還元に追加）",
        "v-point",
        200,
        13,
        requiredSource(sources, 1, "smbc-card-nl eligible stores"),
        {
          ...emptyConditions(),
          merchantIDs: [
            "seicomart", "seven-eleven", "poplar", "ministop", "lawson",
            "mcdonalds", "mos-burger", "kfc", "yoshinoya", "saizeriya",
            "gusto", "bamiya", "syabuyo", "jonathan", "yumean", "sukiya",
            "hamazushi", "cocos", "doutor", "excelsior", "kappazushi"
          ],
          paymentMethods: ["mobileContactless", "applePay", "mobileOrder"],
          activeFrom: "2026-02-01"
        },
        "smbc-eligible-store-mobile-payment-bonus"
      )
    ]
  ),
  freePointsCard(
    {
      id: "epos-card",
      issuerID: "epos-card",
      issuerName: "株式会社エポスカード",
      name: "エポスカード",
      networks: ["visa"],
      applicationURL: "https://www.eposcard.co.jp/index.html",
      eligibilityNote: "申込条件は公式サイトで確認してください",
      pointProgramID: "epos-point",
      sourceURLs: ["https://www.eposcard.co.jp/smp/aflt/index2.html"],
      fallbackTexts: {
        "https://www.eposcard.co.jp/smp/aflt/index2.html": "エポスカード 入会金・年会費永年無料 エポスポイントは1契約のご利用200円(税込)ごとに1ポイント=1円たまる Visa お申し込み"
      }
    },
    [/ご利用([0-9,]+)円(?:\(税込\))?ごとに([0-9,]+)ポイント/]
  ),
  freePointsCard(
    {
      id: "orico-card-the-point",
      issuerID: "orico",
      issuerName: "株式会社オリエントコーポレーション",
      name: "Orico Card THE POINT",
      networks: ["mastercard", "jcb"],
      applicationURL: "https://www.orico.co.jp/creditcard/list/thepoint/",
      eligibilityNote: "満18歳以上の方",
      pointProgramID: "orico-point",
      sourceURLs: ["https://www.orico.co.jp/creditcard/list/thepoint/"]
    },
    [/([0-9,]+)円で([0-9,]+)オリコポイント/]
  ),
  freePointsCard(
    {
      id: "paypay-card",
      issuerID: "paypay-card",
      issuerName: "PayPayカード株式会社",
      name: "PayPayカード",
      networks: ["visa", "mastercard", "jcb"],
      applicationURL: "https://www.paypay-card.co.jp/card/normal/",
      eligibilityNote: "日本国内在住の満18歳以上で本人または配偶者に安定した継続収入がある方、または学生（高校生を除く）",
      pointProgramID: "paypay-point",
      sourceURLs: [
        "https://www.paypay-card.co.jp/service/benefit/point/",
        "https://www.paypay-card.co.jp/service/card/fee/"
      ]
    },
    [/利用金額([0-9,]+)円(?:\(税込\))?につき[^。]{0,40}?([0-9,]+)(?:%|ポイント)/],
    (sources) => {
      const source = requiredSource(sources, 0, "paypay-card");
      return [
      pointsRule(
        "paypay-card-base",
        "通常還元（PayPay連携・本人確認済み）",
        "paypay-point",
        200,
        2,
        source,
        {
          ...emptyConditions(),
          enrollmentKey: "paypay-linked-and-verified",
          activeFrom: "2026-06-02"
        }
      )
      ];
    },
    false
  ),
  freePointsCard(
    {
      id: "aeon-card-waon",
      issuerID: "aeon-card",
      issuerName: "イオンフィナンシャルサービス株式会社",
      name: "イオンカード（WAON一体型）",
      networks: ["visa", "mastercard", "jcb"],
      applicationURL: "https://www.aeon.co.jp/card/lineup/aeoncardwaon/",
      eligibilityNote: "18歳以上（高校生は卒業年度の1月1日以降申込可）",
      pointProgramID: "waon-point",
      sourceURLs: [
        "https://www.aeon.co.jp/card/lineup/aeoncardwaon/",
        "https://www.aeon.co.jp/merit/thanks_day/"
      ],
      fallbackTexts: {
        "https://www.aeon.co.jp/merit/thanks_day/": "毎月20日・30日はお客さま感謝デー。全国のイオン、マックスバリュ、イオンスーパーセンター、サンデー、ザ・ビッグなどでイオンマークのカード払い、AEON Pay、電子マネーWAONのお支払いでお買い物代金が5%OFF。一部対象外商品があります。"
      }
    },
    [/([0-9,]+)円(?:\(税込\))?ごとに([0-9,]+)WAON POINT/],
    (sources) => {
      const source = requiredSource(sources, 0, "aeon-card-waon");
      return [
      pointsRule(
        "aeon-card-waon-aeon-group",
        "イオングループ対象店舗で基本の2倍",
        "waon-point",
        200,
        2,
        source,
        { ...emptyConditions(), merchantIDs: ["aeon-group"] },
        "base"
      ),
      cashbackRule(
        "aeon-card-waon-thanks-day",
        "お客さま感謝デー 5%OFF",
        5,
        requiredSource(sources, 1, "aeon-card-waon thanks day"),
        {
          ...emptyConditions(),
          merchantIDs: ["aeon-group"],
          paymentMethods: ["physical", "contactless"],
          eligibleDaysOfMonth: [20, 30]
        },
        "aeon-thanks-day-discount"
      )
      ];
    }
  )
];

function cashbackRule(
  id: string,
  title: string,
  ratePercent: number,
  source: SourceEvidence,
  conditions = emptyConditions(),
  stackingGroup = "base"
): BenefitRule {
  return {
    id,
    title,
    stackingGroup,
    conditions,
    reward: { kind: "cashbackRate", ratePercent },
    source
  };
}

function requiredSource(sources: SourceEvidence[], index: number, label: string): SourceEvidence {
  const source = sources[index];
  if (!source) throw new Error(`Missing source for ${label}`);
  return source;
}
