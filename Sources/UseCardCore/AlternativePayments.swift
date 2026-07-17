import Foundation

/// A payment route that does not require paying a merchant with the card itself,
/// such as a prepaid balance, QR wallet, or transit IC card.
public struct AlternativePaymentProduct: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let paymentLabel: String
    public let eligibilityNote: String
    public let calculationNote: String?
    public let benefitRules: [BenefitRule]
    public let sources: [SourceEvidence]

    public init(
        id: String,
        name: String,
        paymentLabel: String,
        eligibilityNote: String,
        calculationNote: String? = nil,
        benefitRules: [BenefitRule],
        sources: [SourceEvidence]
    ) {
        self.id = id
        self.name = name
        self.paymentLabel = paymentLabel
        self.eligibilityNote = eligibilityNote
        self.calculationNote = calculationNote
        self.benefitRules = benefitRules
        self.sources = sources
    }
}

public struct AlternativePaymentCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let generatedAt: String
    public let products: [AlternativePaymentProduct]

    public init(schemaVersion: Int, version: String, generatedAt: String, products: [AlternativePaymentProduct]) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.generatedAt = generatedAt
        self.products = products
    }
}

public struct AlternativePaymentRecommendation: Codable, Hashable, Identifiable, Sendable {
    public var id: String { product.id }
    public let product: AlternativePaymentProduct
    public let immediateValueYen: Double
    public let effectiveReturnPercent: Double
    public let appliedBenefits: [AppliedBenefit]
    public let warnings: [String]
}

/// Ranks direct payment methods. Funding-card rewards are deliberately not
/// included, so a card linked to a wallet is never double counted.
public struct AlternativePaymentRecommendationEngine: Sendable {
    public init() {}

    public func rank(
        catalog: AlternativePaymentCatalog,
        intent: PurchaseIntent
    ) -> [AlternativePaymentRecommendation] {
        catalog.products.compactMap { product in
            evaluate(product: product, intent: intent)
        }
        .sorted(by: recommendationOrder)
    }

    private func evaluate(
        product: AlternativePaymentProduct,
        intent: PurchaseIntent
    ) -> AlternativePaymentRecommendation? {
        var bestByGroup: [String: (BenefitRule, Double)] = [:]

        for rule in product.benefitRules where matches(rule.conditions, intent: intent) {
            let value = rewardValue(rule.reward, amountYen: intent.amountYen)
            storeBest(rule: rule, value: value, in: &bestByGroup)
        }

        guard !bestByGroup.isEmpty else { return nil }
        let immediateValue = bestByGroup.values.reduce(0) { $0 + $1.1 }
        let benefits = bestByGroup.values
            .map { rule, value in
                AppliedBenefit(
                    id: rule.id,
                    title: rule.title,
                    valueYen: value,
                    sourceURL: rule.source.url
                )
            }
            .sorted { $0.valueYen > $1.valueYen }
        var warnings: [String] = []
        if product.sources.contains(where: { $0.freshness != .fresh }) {
            warnings.append("公式情報の再確認が必要です")
        }
        let rate = intent.amountYen > 0 ? immediateValue / intent.amountYen * 100 : 0
        return AlternativePaymentRecommendation(
            product: product,
            immediateValueYen: immediateValue,
            effectiveReturnPercent: rate,
            appliedBenefits: benefits,
            warnings: warnings
        )
    }

    private func matches(_ conditions: RuleConditions, intent: PurchaseIntent) -> Bool {
        if !conditions.merchantIDs.isEmpty,
           !conditions.merchantIDs.contains(intent.merchantID ?? "") {
            return false
        }
        if !conditions.categoryIDs.isEmpty,
           !conditions.categoryIDs.contains(intent.categoryID) {
            return false
        }
        if !conditions.channels.isEmpty,
           !conditions.channels.contains(intent.channel) {
            return false
        }
        if !conditions.eligibleDaysOfMonth.isEmpty {
            guard let day = dayOfMonth(from: intent.purchaseDate),
                  conditions.eligibleDaysOfMonth.contains(day) else {
                return false
            }
        }
        if let minimum = conditions.minimumPurchaseYen, intent.amountYen < minimum {
            return false
        }
        if let maximum = conditions.maximumPurchaseYen, intent.amountYen > maximum {
            return false
        }
        if let from = conditions.activeFrom, intent.purchaseDate < from {
            return false
        }
        if let until = conditions.activeUntil, intent.purchaseDate > until {
            return false
        }
        return true
    }

    private func rewardValue(_ reward: RewardFormula, amountYen: Double) -> Double {
        let rawValue: Double
        switch reward.kind {
        case .cashbackRate:
            rawValue = amountYen * (reward.ratePercent ?? 0) / 100
        case .pointsPerUnit:
            let unit = max(reward.unitAmountYen ?? 1, 1)
            rawValue = floor(amountYen / unit) * (reward.pointsPerUnit ?? 0) * (reward.defaultPointValueYen ?? 1)
        case .fixedYen:
            rawValue = reward.fixedYen ?? 0
        }
        if let cap = reward.rewardCapYen {
            return min(rawValue, cap)
        }
        return rawValue
    }

    private func storeBest(
        rule: BenefitRule,
        value: Double,
        in groups: inout [String: (BenefitRule, Double)]
    ) {
        if let current = groups[rule.stackingGroup], current.1 >= value { return }
        groups[rule.stackingGroup] = (rule, value)
    }

    private func recommendationOrder(
        _ lhs: AlternativePaymentRecommendation,
        _ rhs: AlternativePaymentRecommendation
    ) -> Bool {
        if lhs.immediateValueYen != rhs.immediateValueYen {
            return lhs.immediateValueYen > rhs.immediateValueYen
        }
        if lhs.effectiveReturnPercent != rhs.effectiveReturnPercent {
            return lhs.effectiveReturnPercent > rhs.effectiveReturnPercent
        }
        return lhs.product.name.localizedCompare(rhs.product.name) == .orderedAscending
    }

    private func dayOfMonth(from date: String) -> Int? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let day = Int(parts[2]), (1...31).contains(day) else { return nil }
        return day
    }
}
