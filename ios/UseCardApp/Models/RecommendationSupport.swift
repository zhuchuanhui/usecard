import Foundation
import UseCardCore

struct CardRouteRankings {
    let bundle: RecommendationBundle
    let paymentMethodByCardID: [String: PaymentMethod]
}

struct RecommendationCalculator {
    private let cardEngine = RecommendationEngine()
    private let alternativeEngine = AlternativePaymentRecommendationEngine()

    func bestCardRoutes(
        catalog: CardCatalog,
        intent: PurchaseIntent,
        holdings: [UserHolding],
        paymentMethods: [PaymentMethod]
    ) -> CardRouteRankings {
        let methods = paymentMethods.isEmpty ? [intent.paymentMethod] : paymentMethods
        var bestByCardID: [String: (recommendation: CardRecommendation, method: PaymentMethod)] = [:]

        for method in methods {
            let variant = PurchaseIntent(
                amountYen: intent.amountYen,
                merchantID: intent.merchantID,
                categoryID: intent.categoryID,
                paymentMethod: method,
                channel: intent.channel,
                frequency: intent.frequency,
                purchaseDate: intent.purchaseDate
            )
            let ranked = cardEngine.rank(catalog: catalog, intent: variant, holdings: holdings)
            for recommendation in ranked.owned + ranked.available {
                guard let current = bestByCardID[recommendation.card.id] else {
                    bestByCardID[recommendation.card.id] = (recommendation, method)
                    continue
                }
                if isBetter(recommendation, current.recommendation) {
                    bestByCardID[recommendation.card.id] = (recommendation, method)
                }
            }
        }

        let records = Array(bestByCardID.values)
        let owned = records
            .filter { $0.recommendation.isOwned }
            .map(\.recommendation)
            .sorted(by: isBetter)
        let available = records
            .filter { !$0.recommendation.isOwned }
            .map(\.recommendation)
            .sorted(by: isBetter)

        return CardRouteRankings(
            bundle: RecommendationBundle(owned: owned, available: available),
            paymentMethodByCardID: Dictionary(uniqueKeysWithValues: records.map {
                ($0.recommendation.card.id, $0.method)
            })
        )
    }

    func alternativePayments(
        catalog: AlternativePaymentCatalog?,
        intent: PurchaseIntent
    ) -> [AlternativePaymentRecommendation] {
        guard let catalog else { return [] }
        return alternativeEngine.rank(catalog: catalog, intent: intent)
    }

    private func isBetter(_ left: CardRecommendation, _ right: CardRecommendation) -> Bool {
        if left.annualNetValueYen != right.annualNetValueYen {
            return left.annualNetValueYen > right.annualNetValueYen
        }
        if left.immediateValueYen != right.immediateValueYen {
            return left.immediateValueYen > right.immediateValueYen
        }
        return left.card.name.localizedCompare(right.card.name) == .orderedAscending
    }
}
