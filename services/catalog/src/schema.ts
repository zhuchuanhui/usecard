export type CardNetwork =
  | "visa"
  | "mastercard"
  | "jcb"
  | "americanExpress"
  | "dinersClub"
  | "unionPay";

export type ApplicationStatus = "open" | "suspended" | "closed";
export type PaymentMethod =
  | "physical"
  | "contactless"
  | "mobileContactless"
  | "applePay"
  | "mobileOrder"
  | "qr"
  | "online"
  | "recurring";
export type PurchaseChannel = "inStore" | "online";
export type RewardKind = "cashbackRate" | "pointsPerUnit" | "fixedYen";
export type FreshnessStatus = "fresh" | "stale" | "unavailable";

export interface SourceEvidence {
  url: string;
  observedAt: string;
  effectiveFrom?: string;
  contentHash: string;
  freshness: FreshnessStatus;
}

export interface RuleConditions {
  merchantIDs: string[];
  categoryIDs: string[];
  paymentMethods: PaymentMethod[];
  channels: PurchaseChannel[];
  eligibleDaysOfMonth: number[];
  minimumPurchaseYen?: number;
  maximumPurchaseYen?: number;
  minimumAnnualSpendYen?: number;
  enrollmentKey?: string;
  activeFrom?: string;
  activeUntil?: string;
}

export interface RewardFormula {
  kind: RewardKind;
  ratePercent?: number;
  unitAmountYen?: number;
  pointsPerUnit?: number;
  fixedYen?: number;
  pointProgramID?: string;
  defaultPointValueYen?: number;
  rewardCapYen?: number;
}

export interface BenefitRule {
  id: string;
  title: string;
  stackingGroup: string;
  conditions: RuleConditions;
  reward: RewardFormula;
  source: SourceEvidence;
}

export interface CardProduct {
  id: string;
  issuerID: string;
  issuerName: string;
  name: string;
  networks: CardNetwork[];
  annualFeeYen: number;
  applicationStatus: ApplicationStatus;
  applicationURL: string;
  eligibilityNote: string;
  pointProgramID?: string;
  benefitRules: BenefitRule[];
  sources: SourceEvidence[];
}

export interface CardCatalog {
  schemaVersion: number;
  version: string;
  generatedAt: string;
  products: CardProduct[];
}

export interface CatalogManifest {
  schemaVersion: number;
  catalogVersion: string;
  generatedAt: string;
  path: string;
  sha256: string;
  productCount: number;
  issuerCoverage: {
    registryCount: number;
    trackedCount: number;
    pendingCount: number;
  };
}

export interface IssuerRegistryEntry {
  id: string;
  name: string;
  officialURL?: string;
  status: "tracked" | "needsProductAdapter" | "noPublicConsumerCard";
  discoveredAt: string;
}

export const emptyConditions = (): RuleConditions => ({
  merchantIDs: [],
  categoryIDs: [],
  paymentMethods: [],
  channels: [],
  eligibleDaysOfMonth: []
});
