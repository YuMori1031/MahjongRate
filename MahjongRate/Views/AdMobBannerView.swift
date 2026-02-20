//
//  AdMobBannerView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI
import GoogleMobileAds

/// AdMobバナーを表示するSwiftUIラッパー
struct AdMobBannerView: UIViewRepresentable {

    /// AdMob管理コントローラ
    @EnvironmentObject private var admobController: AdmobController

    /// バナー設定モデル
    private let model = AdMobBanner()

    /// バナーViewを生成する
    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: AdSizeBanner)

        bannerView.adUnitID = model.adUnitID

        bannerView.rootViewController = context.coordinator.rootViewController

        bannerView.delegate = context.coordinator

        return bannerView
    }

    /// バナーViewを更新する
    func updateUIView(_ bannerView: BannerView, context: Context) {

        guard admobController.canShowAds else { return }

        bannerView.adSize = AdSizeBanner

        if bannerView.responseInfo == nil {
            let request = model.createAdRequest(
                allowPersonalizedAds: admobController.allowPersonalizedAds
            )
            bannerView.load(request)
        }

        bannerView.rootViewController = context.coordinator.rootViewController
    }

    /// サイズを提案する
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: BannerView,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 50)
    }

    /// Coordinatorを生成する
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// バナーのデリゲートを中継するCoordinator
    final class Coordinator: NSObject, BannerViewDelegate {

        /// ルートViewController
        var rootViewController: UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows
                .first?
                .rootViewController
        }
    }
}

#Preview {
    let admobController = AdmobController()
    admobController.canShowAds = true

    return NavigationStack {
        Color.clear
    }
    .safeAreaInset(edge: .top) {
        AdMobBannerView()
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .background(Color.clear)
    }
    .environmentObject(admobController)
}
