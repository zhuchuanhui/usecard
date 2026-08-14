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
    var pendingName: String?
    var pendingIssuerID: String?
    var pendingIssuerName: String?
    var pendingOfficialURLString: String?

    init(
        cardID: String,
        enrolledBenefitKeys: Set<String> = [],
        annualSpendYen: Double? = nil,
        pointValueYen: Double = 1,
        pendingCandidate: OnlineCardCandidate? = nil
    ) {
        self.cardID = cardID
        self.enrolledBenefitKeysJSON = Self.encode(enrolledBenefitKeys)
        self.annualSpendYen = annualSpendYen ?? 0
        self.hasAnnualSpendEstimate = annualSpendYen != nil
        self.pointValueYen = pointValueYen
        self.createdAt = Date()
        self.pendingName = pendingCandidate?.name
        self.pendingIssuerID = pendingCandidate?.issuerID
        self.pendingIssuerName = pendingCandidate?.issuerName
        self.pendingOfficialURLString = pendingCandidate?.officialURL.absoluteString
    }

    var pendingOfficialURL: URL? {
        guard let pendingOfficialURLString else { return nil }
        return URL(string: pendingOfficialURLString)
    }

    convenience init(sharedRecord: SharedHoldingRecord) {
        self.init(
            cardID: sharedRecord.cardID,
            enrolledBenefitKeys: sharedRecord.enrolledBenefitKeys ?? [],
            annualSpendYen: sharedRecord.annualSpendYen,
            pointValueYen: sharedRecord.pointValueYen ?? 1,
            pendingCandidate: sharedRecord.pendingName.map {
                OnlineCardCandidate(
                    issuerID: sharedRecord.pendingIssuerID ?? "shared",
                    issuerName: sharedRecord.pendingIssuerName ?? "発行会社確認中",
                    name: $0,
                    officialURL: URL(string: sharedRecord.pendingOfficialURLString ?? "https://example.com")!,
                    observedAt: ISO8601DateFormatter().string(from: sharedRecord.updatedAt),
                    aliases: []
                )
            }
        )
        createdAt = sharedRecord.createdAt
        if let hasAnnualSpendEstimate = sharedRecord.hasAnnualSpendEstimate {
            self.hasAnnualSpendEstimate = hasAnnualSpendEstimate
        }
        pendingIssuerName = sharedRecord.pendingIssuerName
        pendingIssuerID = sharedRecord.pendingIssuerID
        pendingOfficialURLString = sharedRecord.pendingOfficialURLString
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

    func sharedRecord(updatedAt: Date = Date()) -> SharedHoldingRecord {
        SharedHoldingRecord(
            cardID: cardID,
            pendingIssuerID: pendingIssuerID,
            pendingName: pendingName,
            pendingIssuerName: pendingIssuerName,
            pendingOfficialURLString: pendingOfficialURLString,
            enrolledBenefitKeys: enrolledBenefitKeys,
            annualSpendYen: hasAnnualSpendEstimate ? annualSpendYen : nil,
            hasAnnualSpendEstimate: hasAnnualSpendEstimate,
            pointValueYen: pointValueYen,
            createdAt: createdAt,
            updatedAt: updatedAt
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
