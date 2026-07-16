import Foundation

public struct RecommendationEngine: Sendable {
    public init() {}

    public func rank(
        catalog: CardCatalog,
        intent: PurchaseIntent,
        holdings: [UserHolding]
    ) -> RecommendationBundle {
        let holdingsByCard = Dictionary(uniqueKeysWithValues: holdings.map { ($0.cardID, $0) })

        let recommendations = catalog.products.compactMap { card -> CardRecommendation? in
            guard card.applicationStatus != .closed || holdingsByCard[card.id] != nil else { return nil }
            return evaluate(
                card: card,
                intent: intent,
                holding: holdingsByCard[card.id]
            )
        }

        let owned = recommendations
            .filter(\.isOwned)
            .sorted(by: recommendationOrder)
        let available = recommendations
            .filter { !$0.isOwned && $0.card.applicationStatus == .open }
            .sorted(by: recommendationOrder)

        return RecommendationBundle(owned: owned, available: available)
    }

    private func evaluate(
        card: CardProduct,
        intent: PurchaseIntent,
        holding: UserHolding?
    ) -> CardRecommendation {
        var guaranteedByGroup: [String: (BenefitRule, Double)] = [:]
        var possibleByGroup: [String: (BenefitRule, Double)] = [:]
        var warnings: [String] = []

        for rule in card.benefitRules {
            let match = matches(rule.conditions, intent: intent, holding: holding)
            guard match != .no else { continue }

            let value = rewardValue(rule.reward, amountYen: intent.amountYen, holding: holding)
            if match == .yes {
                storeBest(rule: rule, value: value, in: &guaranteedByGroup)
            } else {
                warnings.append("\(rule.title)は利用状況の入力後に確定します")
            }
            storeBest(rule: rule, value: value, in: &possibleByGroup)
        }

        let guaranteed = guaranteedByGroup.values.reduce(0) { $0 + $1.1 }
        let possible = possibleByGroup.values.reduce(0) { $0 + $1.1 }
        let annualGross = guaranteed * intent.frequency.annualMultiplier
        let annualNet = annualGross - (holding == nil ? card.annualFeeYen : 0)
        let effectiveRate = intent.amountYen > 0 ? guaranteed / intent.amountYen * 100 : 0

        let benefits = guaranteedByGroup.values
            .map { rule, value in
                AppliedBenefit(
                    id: rule.id,
                    title: rule.title,
                    valueYen: value,
                    sourceURL: rule.source.url
                )
            }
            .sorted { $0.valueYen > $1.valueYen }

        if card.sources.contains(where: { $0.freshness != .fresh }) {
            warnings.append("公式情報の再確認が必要です")
        }

        return CardRecommendation(
            card: card,
            isOwned: holding != nil,
            immediateValueYen: guaranteed,
            possibleImmediateValueYen: max(guaranteed, possible),
            effectiveReturnPercent: effectiveRate,
            annualNetValueYen: annualNet,
            appliedBenefits: benefits,
            warnings: Array(Set(warnings)).sorted()
        )
    }

    private enum MatchResult {
        case yes
        case possible
        case no
    }

    private func matches(
        _ conditions: RuleConditions,
        intent: PurchaseIntent,
        holding: UserHolding?
    ) -> MatchResult {
        if !conditions.merchantIDs.isEmpty,
           !conditions.merchantIDs.contains(intent.merchantID ?? "") {
            return .no
        }
        if !conditions.categoryIDs.isEmpty,
           !conditions.categoryIDs.contains(intent.categoryID) {
            return .no
        }
        if !conditions.paymentMethods.isEmpty,
           !conditions.paymentMethods.contains(intent.paymentMethod) {
            return .no
        }
        if !conditions.channels.isEmpty,
           !conditions.channels.contains(intent.channel) {
            return .no
        }
        if !conditions.eligibleDaysOfMonth.isEmpty {
            guard let day = dayOfMonth(from: intent.purchaseDate),
                  conditions.eligibleDaysOfMonth.contains(day) else {
                return .no
            }
        }
        if let minimum = conditions.minimumPurchaseYen, intent.amountYen < minimum {
            return .no
        }
        if let maximum = conditions.maximumPurchaseYen, intent.amountYen > maximum {
            return .no
        }
        if let from = conditions.activeFrom, intent.purchaseDate < from {
            return .no
        }
        if let until = conditions.activeUntil, intent.purchaseDate > until {
            return .no
        }

        if let enrollmentKey = conditions.enrollmentKey {
            guard let holding else { return .possible }
            if !holding.enrolledBenefitKeys.contains(enrollmentKey) { return .no }
        }
        if let minimumAnnualSpend = conditions.minimumAnnualSpendYen {
            guard let annualSpend = holding?.annualSpendYen else {
                return .possible
            }
            if annualSpend < minimumAnnualSpend { return .no }
        }
        return .yes
    }

    private func dayOfMonth(from date: String) -> Int? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let day = Int(parts[2]), (1...31).contains(day) else { return nil }
        return day
    }

    private func rewardValue(
        _ reward: RewardFormula,
        amountYen: Double,
        holding: UserHolding?
    ) -> Double {
        let rawValue: Double
        switch reward.kind {
        case .cashbackRate:
            rawValue = amountYen * (reward.ratePercent ?? 0) / 100
        case .pointsPerUnit:
            let unit = max(reward.unitAmountYen ?? 1, 1)
            let points = floor(amountYen / unit) * (reward.pointsPerUnit ?? 0)
            let programID = reward.pointProgramID ?? ""
            let pointValue = holding?.pointValueOverrides[programID]
                ?? reward.defaultPointValueYen
                ?? 1
            rawValue = points * pointValue
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
        _ lhs: CardRecommendation,
        _ rhs: CardRecommendation
    ) -> Bool {
        if lhs.annualNetValueYen == rhs.annualNetValueYen {
            return lhs.immediateValueYen > rhs.immediateValueYen
        }
        return lhs.annualNetValueYen > rhs.annualNetValueYen
    }
}
