import XCTest
@testable import UseCardCore

final class RecommendationEngineTests: XCTestCase {
    func testPointsAreRoundedDownByUnit() throws {
        let card = makeCard(
            id: "unit-card",
            annualFee: 0,
            reward: RewardFormula(
                kind: .pointsPerUnit,
                unitAmountYen: 200,
                pointsPerUnit: 1,
                pointProgramID: "points",
                defaultPointValueYen: 1
            )
        )
        let result = RecommendationEngine().rank(
            catalog: CardCatalog(schemaVersion: 1, version: "test", generatedAt: "2026-07-16T00:00:00Z", products: [card]),
            intent: intent(amount: 1_100),
            holdings: [UserHolding(cardID: card.id)]
        )

        XCTAssertEqual(result.owned.first?.immediateValueYen, 5)
        XCTAssertEqual(result.owned.first?.effectiveReturnPercent ?? 0, 5.0 / 1_100.0 * 100, accuracy: 0.0001)
    }

    func testUnownedCardSubtractsAnnualFee() throws {
        let free = makeCard(
            id: "free",
            annualFee: 0,
            reward: RewardFormula(kind: .cashbackRate, ratePercent: 1)
        )
        let paid = makeCard(
            id: "paid",
            annualFee: 11_000,
            reward: RewardFormula(kind: .cashbackRate, ratePercent: 2)
        )
        let result = RecommendationEngine().rank(
            catalog: CardCatalog(schemaVersion: 1, version: "test", generatedAt: "2026-07-16T00:00:00Z", products: [paid, free]),
            intent: intent(amount: 10_000, frequency: .monthly),
            holdings: []
        )

        XCTAssertEqual(result.available.map(\.card.id), ["free", "paid"])
        XCTAssertEqual(result.available.first?.annualNetValueYen, 1_200)
    }

    func testUnknownSpendThresholdIsShownAsPossibleButNotGuaranteed() throws {
        let source = sourceEvidence()
        let card = CardProduct(
            id: "threshold",
            issuerID: "issuer",
            issuerName: "Issuer",
            name: "Threshold Card",
            networks: [.visa],
            annualFeeYen: 0,
            applicationStatus: .open,
            applicationURL: source.url,
            eligibilityNote: "",
            pointProgramID: nil,
            benefitRules: [
                BenefitRule(
                    id: "threshold-base",
                    title: "通常還元",
                    stackingGroup: "base",
                    conditions: RuleConditions(),
                    reward: RewardFormula(kind: .cashbackRate, ratePercent: 0.5),
                    source: source
                ),
                BenefitRule(
                    id: "threshold-bonus",
                    title: "年間利用ボーナス",
                    stackingGroup: "annual-bonus",
                    conditions: RuleConditions(minimumAnnualSpendYen: 1_000_000),
                    reward: RewardFormula(kind: .cashbackRate, ratePercent: 1),
                    source: source
                )
            ],
            sources: [source]
        )

        let result = RecommendationEngine().rank(
            catalog: CardCatalog(schemaVersion: 1, version: "test", generatedAt: "2026-07-16T00:00:00Z", products: [card]),
            intent: intent(amount: 10_000),
            holdings: [UserHolding(cardID: card.id)]
        )

        XCTAssertEqual(result.owned.first?.immediateValueYen, 50)
        XCTAssertEqual(result.owned.first?.possibleImmediateValueYen, 150)
        XCTAssertFalse(result.owned.first?.warnings.isEmpty ?? true)
    }

    func testUsualSpendingExcludesStoreAndPaymentSpecificRewards() throws {
        let source = sourceEvidence()
        let card = CardProduct(
            id: "usual",
            issuerID: "issuer",
            issuerName: "Issuer",
            name: "Usual Card",
            networks: [.visa],
            annualFeeYen: 0,
            applicationStatus: .open,
            applicationURL: source.url,
            eligibilityNote: "",
            pointProgramID: nil,
            benefitRules: [
                BenefitRule(
                    id: "usual-base",
                    title: "通常還元",
                    stackingGroup: "base",
                    conditions: RuleConditions(),
                    reward: RewardFormula(kind: .cashbackRate, ratePercent: 1),
                    source: source
                ),
                BenefitRule(
                    id: "usual-store-bonus",
                    title: "対象店タッチ決済",
                    stackingGroup: "store-bonus",
                    conditions: RuleConditions(merchantIDs: ["seven-eleven"], paymentMethods: [.contactless]),
                    reward: RewardFormula(kind: .cashbackRate, ratePercent: 6),
                    source: source
                )
            ],
            sources: [source]
        )

        let result = RecommendationEngine().rankUsualSpending(
            catalog: CardCatalog(schemaVersion: 1, version: "test", generatedAt: "2026-07-16T00:00:00Z", products: [card]),
            holdings: [UserHolding(cardID: card.id)],
            purchaseDate: "2026-07-16"
        )

        XCTAssertEqual(result.owned.first?.immediateValueYen, 100)
        XCTAssertEqual(result.owned.first?.appliedBenefits.map(\.title), ["通常還元"])
    }

    func testMobileTouchBonusUsesTheSame200YenRoundingAsBasePoints() throws {
        let source = sourceEvidence()
        let card = CardProduct(
            id: "store-bonus",
            issuerID: "issuer",
            issuerName: "Issuer",
            name: "Store Bonus Card",
            networks: [.visa],
            annualFeeYen: 0,
            applicationStatus: .open,
            applicationURL: source.url,
            eligibilityNote: "",
            pointProgramID: "points",
            benefitRules: [
                BenefitRule(
                    id: "base",
                    title: "通常還元",
                    stackingGroup: "base",
                    conditions: RuleConditions(),
                    reward: RewardFormula(kind: .pointsPerUnit, unitAmountYen: 200, pointsPerUnit: 1, pointProgramID: "points", defaultPointValueYen: 1),
                    source: source
                ),
                BenefitRule(
                    id: "mobile-touch",
                    title: "対象店での追加還元",
                    stackingGroup: "eligible-store-bonus",
                    conditions: RuleConditions(merchantIDs: ["seven-eleven"], paymentMethods: [.mobileContactless]),
                    reward: RewardFormula(kind: .pointsPerUnit, unitAmountYen: 200, pointsPerUnit: 13, pointProgramID: "points", defaultPointValueYen: 1),
                    source: source
                )
            ],
            sources: [source]
        )

        let result = RecommendationEngine().rank(
            catalog: CardCatalog(schemaVersion: 1, version: "test", generatedAt: "2026-07-16T00:00:00Z", products: [card]),
            intent: PurchaseIntent(
                amountYen: 1_099,
                merchantID: "seven-eleven",
                categoryID: "general",
                paymentMethod: .mobileContactless,
                channel: .inStore,
                frequency: .once,
                purchaseDate: "2026-07-16"
            ),
            holdings: [UserHolding(cardID: card.id)]
        )

        XCTAssertEqual(result.owned.first?.immediateValueYen, 70)
    }

    func testDaySpecificDiscountOnlyAppliesOnEligibleDay() throws {
        let card = makeCard(
            id: "thanks-day",
            annualFee: 0,
            reward: RewardFormula(kind: .cashbackRate, ratePercent: 5)
        )
        let source = sourceEvidence()
        let daySpecificCard = CardProduct(
            id: card.id,
            issuerID: card.issuerID,
            issuerName: card.issuerName,
            name: card.name,
            networks: card.networks,
            annualFeeYen: card.annualFeeYen,
            applicationStatus: card.applicationStatus,
            applicationURL: card.applicationURL,
            eligibilityNote: card.eligibilityNote,
            pointProgramID: card.pointProgramID,
            benefitRules: [
                BenefitRule(
                    id: "thanks-day-discount",
                    title: "感謝デー割引",
                    stackingGroup: "discount",
                    conditions: RuleConditions(merchantIDs: ["aeon-group"], eligibleDaysOfMonth: [20, 30]),
                    reward: RewardFormula(kind: .cashbackRate, ratePercent: 5),
                    source: source
                )
            ],
            sources: [source]
        )
        let catalog = CardCatalog(schemaVersion: 1, version: "test", generatedAt: "2026-07-16T00:00:00Z", products: [daySpecificCard])

        let onEligibleDay = RecommendationEngine().rank(
            catalog: catalog,
            intent: PurchaseIntent(amountYen: 1_000, merchantID: "aeon-group", categoryID: "groceries", paymentMethod: .physical, channel: .inStore, frequency: .once, purchaseDate: "2026-07-20"),
            holdings: [UserHolding(cardID: daySpecificCard.id)]
        )
        let onOtherDay = RecommendationEngine().rank(
            catalog: catalog,
            intent: PurchaseIntent(amountYen: 1_000, merchantID: "aeon-group", categoryID: "groceries", paymentMethod: .physical, channel: .inStore, frequency: .once, purchaseDate: "2026-07-21"),
            holdings: [UserHolding(cardID: daySpecificCard.id)]
        )

        XCTAssertEqual(onEligibleDay.owned.first?.immediateValueYen, 50)
        XCTAssertEqual(onOtherDay.owned.first?.immediateValueYen, 0)
    }

    private func makeCard(id: String, annualFee: Double, reward: RewardFormula) -> CardProduct {
        let source = sourceEvidence()
        return CardProduct(
            id: id,
            issuerID: "issuer",
            issuerName: "Issuer",
            name: id,
            networks: [.visa],
            annualFeeYen: annualFee,
            applicationStatus: .open,
            applicationURL: source.url,
            eligibilityNote: "",
            pointProgramID: reward.pointProgramID,
            benefitRules: [
                BenefitRule(
                    id: "\(id)-base",
                    title: "通常還元",
                    stackingGroup: "base",
                    conditions: RuleConditions(),
                    reward: reward,
                    source: source
                )
            ],
            sources: [source]
        )
    }

    private func sourceEvidence() -> SourceEvidence {
        SourceEvidence(
            url: URL(string: "https://example.com/card")!,
            observedAt: "2026-07-16T00:00:00Z",
            contentHash: "test",
            freshness: .fresh
        )
    }

    private func intent(
        amount: Double,
        frequency: SpendFrequency = .once
    ) -> PurchaseIntent {
        PurchaseIntent(
            amountYen: amount,
            categoryID: "general",
            paymentMethod: .physical,
            channel: .inStore,
            frequency: frequency,
            purchaseDate: "2026-07-16"
        )
    }
}
