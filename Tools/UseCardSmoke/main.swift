import Foundation

let catalogURL = URL(fileURLWithPath: "catalog/public/latest.json")
let catalog = try JSONDecoder().decode(CardCatalog.self, from: Data(contentsOf: catalogURL))
let alternativePaymentsURL = URL(fileURLWithPath: "catalog/public/payment-alternatives.json")
let alternativePayments = try JSONDecoder().decode(
    AlternativePaymentCatalog.self,
    from: Data(contentsOf: alternativePaymentsURL)
)
precondition(catalog.schemaVersion == 1)
precondition(catalog.products.count >= 5)
precondition(alternativePayments.schemaVersion == 1)
precondition(alternativePayments.products.count >= 5)

let intent = PurchaseIntent(
    amountYen: 10_000,
    merchantID: "aeon-group",
    categoryID: "groceries",
    paymentMethod: .physical,
    channel: .inStore,
    frequency: .monthly,
    purchaseDate: "2026-07-20"
)
let holdings = [UserHolding(cardID: "jcb-card-s")]
let result = RecommendationEngine().rank(catalog: catalog, intent: intent, holdings: holdings)

precondition(result.owned.first?.card.id == "jcb-card-s")
precondition(result.available.first?.card.id == "aeon-card-waon")

let smbcMobileIntent = PurchaseIntent(
    amountYen: 1_000,
    merchantID: "seven-eleven",
    categoryID: "dining",
    paymentMethod: .mobileContactless,
    channel: .inStore,
    frequency: .once,
    purchaseDate: "2026-07-16"
)
let smbcMobile = RecommendationEngine().rank(
    catalog: catalog,
    intent: smbcMobileIntent,
    holdings: [UserHolding(cardID: "smbc-card-nl")]
)
precondition(smbcMobile.owned.first?.immediateValueYen == 70)

let smbcPhysicalTouch = RecommendationEngine().rank(
    catalog: catalog,
    intent: PurchaseIntent(
        amountYen: 1_000,
        merchantID: "seven-eleven",
        categoryID: "dining",
        paymentMethod: .contactless,
        channel: .inStore,
        frequency: .once,
        purchaseDate: "2026-07-16"
    ),
    holdings: [UserHolding(cardID: "smbc-card-nl")]
)
precondition(smbcPhysicalTouch.owned.first?.immediateValueYen == 5)

let aeonThanksDay = RecommendationEngine().rank(
    catalog: catalog,
    intent: PurchaseIntent(
        amountYen: 1_000,
        merchantID: "aeon-group",
        categoryID: "groceries",
        paymentMethod: .physical,
        channel: .inStore,
        frequency: .once,
        purchaseDate: "2026-07-20"
    ),
    holdings: [UserHolding(cardID: "aeon-card-waon")]
)
precondition(aeonThanksDay.owned.first?.immediateValueYen == 60)

let rakutenMarket = RecommendationEngine().rank(
    catalog: catalog,
    intent: PurchaseIntent(
        amountYen: 1_000,
        merchantID: "rakuten-market",
        categoryID: "online-shopping",
        paymentMethod: .online,
        channel: .online,
        frequency: .once,
        purchaseDate: "2026-07-16"
    ),
    holdings: [UserHolding(cardID: "rakuten-card")]
)
precondition(rakutenMarket.owned.first?.immediateValueYen == 20)

let amazon = RecommendationEngine().rank(
    catalog: catalog,
    intent: PurchaseIntent(
        amountYen: 1_000,
        merchantID: "amazon",
        categoryID: "online-shopping",
        paymentMethod: .online,
        channel: .online,
        frequency: .once,
        purchaseDate: "2026-07-17"
    ),
    holdings: [UserHolding(cardID: "amazon-mastercard")]
)
precondition(amazon.owned.first?.card.id == "amazon-mastercard")
precondition(amazon.owned.first?.immediateValueYen == 15)

let alternativeSeven = AlternativePaymentRecommendationEngine().rank(
    catalog: alternativePayments,
    intent: PurchaseIntent(
        amountYen: 500,
        merchantID: "seven-eleven",
        categoryID: "general",
        paymentMethod: .physical,
        channel: .inStore,
        frequency: .once,
        purchaseDate: "2026-07-17"
    )
)
precondition(alternativeSeven.first?.product.id == "rakuten-pay-cash")
precondition(alternativeSeven.contains { $0.product.id == "nanaco-seven-eleven" && $0.immediateValueYen == 2 })

let alternativeJREastRail = AlternativePaymentRecommendationEngine().rank(
    catalog: alternativePayments,
    intent: PurchaseIntent(
        amountYen: 1_000,
        merchantID: "jr-east-rail",
        categoryID: "transport",
        paymentMethod: .physical,
        channel: .inStore,
        frequency: .once,
        purchaseDate: "2026-07-17"
    )
)
precondition(alternativeJREastRail.first?.product.id == "mobile-suica-jre-point")
precondition(alternativeJREastRail.first?.immediateValueYen == 20)

print("UseCard smoke passed: \(catalog.products.count) cards and \(alternativePayments.products.count) payment routes, catalog \(catalog.version)")
