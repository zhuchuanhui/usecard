import Foundation

public enum CardNetwork: String, Codable, CaseIterable, Sendable {
    case visa
    case mastercard
    case jcb
    case americanExpress
    case dinersClub
    case unionPay
}

public enum ApplicationStatus: String, Codable, Sendable {
    case open
    case suspended
    case closed
}

public enum PaymentMethod: String, Codable, CaseIterable, Sendable {
    case physical
    case contactless
    case mobileContactless
    case applePay
    case mobileOrder
    case qr
    case online
    case recurring
}

public enum PurchaseChannel: String, Codable, CaseIterable, Sendable {
    case inStore
    case online
}

public enum SpendFrequency: String, Codable, CaseIterable, Sendable {
    case once
    case monthly
    case quarterly
    case annually

    public var annualMultiplier: Double {
        switch self {
        case .once, .annually: 1
        case .monthly: 12
        case .quarterly: 4
        }
    }
}

public enum RewardKind: String, Codable, Sendable {
    case cashbackRate
    case pointsPerUnit
    case fixedYen
}

public enum FreshnessStatus: String, Codable, Sendable {
    case fresh
    case stale
    case unavailable
}

public struct SourceEvidence: Codable, Hashable, Sendable {
    public let url: URL
    public let observedAt: String
    public let effectiveFrom: String?
    public let contentHash: String
    public let freshness: FreshnessStatus

    public init(
        url: URL,
        observedAt: String,
        effectiveFrom: String? = nil,
        contentHash: String,
        freshness: FreshnessStatus
    ) {
        self.url = url
        self.observedAt = observedAt
        self.effectiveFrom = effectiveFrom
        self.contentHash = contentHash
        self.freshness = freshness
    }
}

public struct RuleConditions: Codable, Hashable, Sendable {
    public let merchantIDs: [String]
    public let categoryIDs: [String]
    public let paymentMethods: [PaymentMethod]
    public let channels: [PurchaseChannel]
    public let eligibleDaysOfMonth: [Int]
    public let minimumPurchaseYen: Double?
    public let maximumPurchaseYen: Double?
    public let minimumAnnualSpendYen: Double?
    public let enrollmentKey: String?
    public let activeFrom: String?
    public let activeUntil: String?

    public init(
        merchantIDs: [String] = [],
        categoryIDs: [String] = [],
        paymentMethods: [PaymentMethod] = [],
        channels: [PurchaseChannel] = [],
        eligibleDaysOfMonth: [Int] = [],
        minimumPurchaseYen: Double? = nil,
        maximumPurchaseYen: Double? = nil,
        minimumAnnualSpendYen: Double? = nil,
        enrollmentKey: String? = nil,
        activeFrom: String? = nil,
        activeUntil: String? = nil
    ) {
        self.merchantIDs = merchantIDs
        self.categoryIDs = categoryIDs
        self.paymentMethods = paymentMethods
        self.channels = channels
        self.eligibleDaysOfMonth = eligibleDaysOfMonth
        self.minimumPurchaseYen = minimumPurchaseYen
        self.maximumPurchaseYen = maximumPurchaseYen
        self.minimumAnnualSpendYen = minimumAnnualSpendYen
        self.enrollmentKey = enrollmentKey
        self.activeFrom = activeFrom
        self.activeUntil = activeUntil
    }
}

public struct RewardFormula: Codable, Hashable, Sendable {
    public let kind: RewardKind
    public let ratePercent: Double?
    public let unitAmountYen: Double?
    public let pointsPerUnit: Double?
    public let fixedYen: Double?
    public let pointProgramID: String?
    public let defaultPointValueYen: Double?
    public let rewardCapYen: Double?

    public init(
        kind: RewardKind,
        ratePercent: Double? = nil,
        unitAmountYen: Double? = nil,
        pointsPerUnit: Double? = nil,
        fixedYen: Double? = nil,
        pointProgramID: String? = nil,
        defaultPointValueYen: Double? = nil,
        rewardCapYen: Double? = nil
    ) {
        self.kind = kind
        self.ratePercent = ratePercent
        self.unitAmountYen = unitAmountYen
        self.pointsPerUnit = pointsPerUnit
        self.fixedYen = fixedYen
        self.pointProgramID = pointProgramID
        self.defaultPointValueYen = defaultPointValueYen
        self.rewardCapYen = rewardCapYen
    }
}

public struct BenefitRule: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let stackingGroup: String
    public let conditions: RuleConditions
    public let reward: RewardFormula
    public let source: SourceEvidence

    public init(
        id: String,
        title: String,
        stackingGroup: String,
        conditions: RuleConditions,
        reward: RewardFormula,
        source: SourceEvidence
    ) {
        self.id = id
        self.title = title
        self.stackingGroup = stackingGroup
        self.conditions = conditions
        self.reward = reward
        self.source = source
    }
}

public struct CardProduct: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let issuerID: String
    public let issuerName: String
    public let name: String
    public let networks: [CardNetwork]
    public let annualFeeYen: Double
    public let applicationStatus: ApplicationStatus
    public let applicationURL: URL
    public let eligibilityNote: String
    public let pointProgramID: String?
    public let benefitRules: [BenefitRule]
    public let sources: [SourceEvidence]

    public init(
        id: String,
        issuerID: String,
        issuerName: String,
        name: String,
        networks: [CardNetwork],
        annualFeeYen: Double,
        applicationStatus: ApplicationStatus,
        applicationURL: URL,
        eligibilityNote: String,
        pointProgramID: String?,
        benefitRules: [BenefitRule],
        sources: [SourceEvidence]
    ) {
        self.id = id
        self.issuerID = issuerID
        self.issuerName = issuerName
        self.name = name
        self.networks = networks
        self.annualFeeYen = annualFeeYen
        self.applicationStatus = applicationStatus
        self.applicationURL = applicationURL
        self.eligibilityNote = eligibilityNote
        self.pointProgramID = pointProgramID
        self.benefitRules = benefitRules
        self.sources = sources
    }
}

public struct CardCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let generatedAt: String
    public let products: [CardProduct]

    public init(schemaVersion: Int, version: String, generatedAt: String, products: [CardProduct]) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.generatedAt = generatedAt
        self.products = products
    }
}

public struct UserHolding: Codable, Hashable, Sendable {
    public let cardID: String
    public var enrolledBenefitKeys: Set<String>
    public var annualSpendYen: Double?
    public var pointValueOverrides: [String: Double]

    public init(
        cardID: String,
        enrolledBenefitKeys: Set<String> = [],
        annualSpendYen: Double? = nil,
        pointValueOverrides: [String: Double] = [:]
    ) {
        self.cardID = cardID
        self.enrolledBenefitKeys = enrolledBenefitKeys
        self.annualSpendYen = annualSpendYen
        self.pointValueOverrides = pointValueOverrides
    }
}

public struct PurchaseIntent: Codable, Hashable, Sendable {
    public let amountYen: Double
    public let merchantID: String?
    public let categoryID: String
    public let paymentMethod: PaymentMethod
    public let channel: PurchaseChannel
    public let frequency: SpendFrequency
    public let purchaseDate: String

    public init(
        amountYen: Double,
        merchantID: String? = nil,
        categoryID: String,
        paymentMethod: PaymentMethod,
        channel: PurchaseChannel,
        frequency: SpendFrequency,
        purchaseDate: String
    ) {
        self.amountYen = amountYen
        self.merchantID = merchantID
        self.categoryID = categoryID
        self.paymentMethod = paymentMethod
        self.channel = channel
        self.frequency = frequency
        self.purchaseDate = purchaseDate
    }
}

public struct AppliedBenefit: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let valueYen: Double
    public let sourceURL: URL
}

public struct CardRecommendation: Codable, Hashable, Identifiable, Sendable {
    public var id: String { card.id }
    public let card: CardProduct
    public let isOwned: Bool
    public let immediateValueYen: Double
    public let possibleImmediateValueYen: Double
    public let effectiveReturnPercent: Double
    public let annualNetValueYen: Double
    public let appliedBenefits: [AppliedBenefit]
    public let warnings: [String]
}

public struct RecommendationBundle: Codable, Sendable {
    public let owned: [CardRecommendation]
    public let available: [CardRecommendation]
}
