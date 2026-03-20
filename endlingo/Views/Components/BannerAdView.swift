import SwiftUI
import GoogleMobileAds

/// AdMob 배너 광고 (하단 고정용, 로드 실패 시 숨김)
struct BannerAdView: View {
    @State private var adHeight: CGFloat = 0

    var body: some View {
        BannerAdRepresentable(adHeight: $adHeight)
            .frame(height: adHeight)
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    @Binding var adHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(adHeight: $adHeight)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let screenWidth = UIScreen.main.bounds.width
        let adSize = inlineAdaptiveBanner(width: screenWidth, maxHeight: 60)
        let banner = BannerView(adSize: adSize)

        #if DEBUG
        banner.adUnitID = "ca-app-pub-3940256099942544/2435281174"
        #else
        banner.adUnitID = "ca-app-pub-4582716621646848/8738604795"
        #endif
        banner.delegate = context.coordinator

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
        }

        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        banner.load(Request())
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    class Coordinator: NSObject, BannerViewDelegate {
        @Binding var adHeight: CGFloat

        init(adHeight: Binding<CGFloat>) {
            _adHeight = adHeight
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            withAnimation {
                adHeight = bannerView.adSize.size.height
            }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("[Ad] 배너 로드 실패: \(error.localizedDescription)")
            withAnimation { adHeight = 0 }
        }
    }
}
