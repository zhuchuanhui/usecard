import Foundation
import SwiftData
import UseCardCore

@Model
final class HoldingRecord {
    var cardID: String = ""
    var enrolledBenefitKeysJSON: String = "[]"
    var annualSpendYen: Double = 0
    var hasAnnualSpendEstimate: Bool = false
    var pointValueYen: Double = 1
    var createdAt: Date = Date()

    init(
        cardID: String,
        enrolledBenefitKeys: Set<String> = [],
        annualSpendYen: Double? = nil,
        pointValueYen: Double = 1
    ) {
        self.cardID = cardID
        self.enrolledBenefitKeysJSON = Self.encode(enrolledBenefitKeys)
        self.annualSpendYen = annualSpendYen ?? 0
        self.hasAnnualSpendEstimate = annualSpendYen != nil
        self.pointValueYen = pointValueYen
        self.createdAt = Date()
    }

    var enrolledBenefitKeys: Set<String> {
        get {
            guard let data = enrolledBenefitKeysJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            enrolledBenefitKeysJSON = Self.encode(newValue)
        }
    }

    func domainHolding(pointProgramID: String?) -> UserHolding {
        var overrides: [String: Double] = [:]
        if let pointProgramID {
            overrides[pointProgramID] = pointValueYen
        }
        return UserHolding(
            cardID: cardID,
            enrolledBenefitKeys: enrolledBenefitKeys,
            annualSpendYen: hasAnnualSpendEstimate ? annualSpendYen : nil,
            pointValueOverrides: overrides
        )
    }

    private static func encode(_ value: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
