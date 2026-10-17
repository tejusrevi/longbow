import SwiftUI

/// PART B (spec B2.2). v1.0 ships `NoOpMonetizationService` only: nothing is
/// sold, no store or ads code runs, and every slot view renders nothing.
enum MonetizationFeature {
    case shop, iap, seasonPass, rewardedAds, premiumAccent, paidNameChange, streakProtection
}

enum StorePlacement { case shop, results }
enum AdPlacement { case matchResult, dailyShotResult, streak }

struct StoreProduct: Identifiable {
    let id: String
    let displayName: String
    let displayPrice: String
}

enum PurchaseResult { case success, cancelled, pending }
enum AdResult { case rewarded, skipped, unavailable }

protocol MonetizationService: AnyObject {
    var isEnabled: Bool { get }
    func isEnabled(_ feature: MonetizationFeature) -> Bool
    func products(for placement: StorePlacement) async -> [StoreProduct]
    func purchase(_ productId: String) async throws -> PurchaseResult
    func restorePurchases() async throws
    func canShowRewardedAd(for placement: AdPlacement) -> Bool
    func showRewardedAd(for placement: AdPlacement) async -> AdResult
}

final class NoOpMonetizationService: MonetizationService {
    var isEnabled: Bool { false }
    func isEnabled(_ feature: MonetizationFeature) -> Bool { false }
    func products(for placement: StorePlacement) async -> [StoreProduct] { [] }
    func purchase(_ productId: String) async throws -> PurchaseResult { .cancelled }
    func restorePurchases() async throws {}
    func canShowRewardedAd(for placement: AdPlacement) -> Bool { false }
    func showRewardedAd(for placement: AdPlacement) async -> AdResult { .unavailable }
}

// MARK: - Slots (B2.3): render nothing and take no space while disabled.

struct ShopEntrySlot: View {
    @Environment(\.services) private var services
    var body: some View {
        if services.monetization.isEnabled(.shop) { EmptyView() /* Shop entry — PART B */ }
    }
}

struct RewardedAdSlot: View {
    @Environment(\.services) private var services
    let placement: AdPlacement
    var body: some View {
        if services.monetization.canShowRewardedAd(for: placement) { EmptyView() /* PART B */ }
    }
}

struct SeasonTrackSlot: View {
    @Environment(\.services) private var services
    var body: some View {
        if services.monetization.isEnabled(.seasonPass) { EmptyView() /* PART B */ }
    }
}
