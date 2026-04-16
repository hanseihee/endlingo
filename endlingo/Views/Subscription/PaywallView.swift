import SwiftUI
import RevenueCat

/// Premium 구독 구매 화면.
/// PhoneCallLauncherView의 blockingNotice 또는 프로필에서 sheet로 표시.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscription = SubscriptionService.shared

    @State private var offering: Offering?
    @State private var selectedPackage: Package?
    @State private var errorMessage: String?
    @State private var showRestoreSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    benefitsSection
                    if let offering {
                        packagesSection(offering)
                    } else {
                        ProgressView()
                            .padding(40)
                    }
                    purchaseButton
                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .task {
                do {
                    offering = try await subscription.loadCurrentOffering()
                    // 연간을 기본 선택 (할인 강조)
                    selectedPackage = offering?.annual ?? offering?.monthly
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("구매 복원 완료", isPresented: $showRestoreSuccess) {
                Button("확인") {
                    if subscription.isPremium { dismiss() }
                }
            }
            .onChange(of: subscription.isPremium) { _, isPremium in
                if isPremium { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("endlingo Premium")
                .font(.title2.bold())

            Text("영어 실력을 더 빠르게 키우세요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow(icon: "phone.fill", color: .green, title: "AI 전화영어 하루 10분", subtitle: "무료 1분 → 10분으로 확장")
            benefitRow(icon: "globe", color: .blue, title: "실시간 번역", subtitle: "통화 중 실시간 한국어 번역")
            benefitRow(icon: "text.badge.checkmark", color: .purple, title: "영작 피드백", subtitle: "통화 후 문장 교정")
            benefitRow(icon: "nosign", color: .red, title: "광고 제거", subtitle: "모든 배너 광고 제거")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func benefitRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Packages

    private func packagesSection(_ offering: Offering) -> some View {
        VStack(spacing: 10) {
            if let annual = offering.annual {
                packageCard(annual, label: "연간", badge: "BEST VALUE")
            }
            if let monthly = offering.monthly {
                packageCard(monthly, label: "월간", badge: nil)
            }
        }
    }

    private func packageCard(_ package: Package, label: String, badge: String?) -> some View {
        let isSelected = selectedPackage?.identifier == package.identifier
        return Button {
            selectedPackage = package
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.callout.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                    }
                    if let intro = package.storeProduct.introductoryDiscount,
                       intro.price == 0 {
                        Text("7일 무료 체험")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Text(package.localizedPriceString)
                    .font(.body.weight(.semibold))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Purchase

    private var purchaseButton: some View {
        VStack(spacing: 10) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                guard let package = selectedPackage else { return }
                Task {
                    do {
                        errorMessage = nil
                        let purchased = try await subscription.purchase(package: package)
                        if purchased {
                            dismiss()
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if subscription.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("무료 체험 시작")
                            .font(.body.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedPackage == nil || subscription.isLoading)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    do {
                        try await subscription.restore()
                        showRestoreSuccess = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Text("구매 복원")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("구독은 언제든 해지할 수 있습니다. 무료 체험 기간이 끝나면 자동으로 결제됩니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 16)
    }
}
