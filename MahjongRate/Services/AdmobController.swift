//
//  AdmobController.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import GoogleMobileAds
import AppTrackingTransparency
import UserMessagingPlatform
import Combine

/// AdMobの初期化と表示可否を管理するコントローラ
@MainActor
final class AdmobController: ObservableObject {
    /// 広告を表示可能かどうか
    @Published var canShowAds: Bool = false

    /// パーソナライズ広告を許可するかどうか
    var allowPersonalizedAds: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .authorized
    }

    private var didStartAds = false

    /// 広告表示に必要な準備を行う
    func prepare() async {
        await requestIDFAMessageIfNeeded()
        _ = await ATTrackingManager.requestTrackingAuthorization()
        if !didStartAds {
            didStartAds = true
            await MobileAds.shared.start()
        }

        canShowAds = true
    }

    /// 同意フォームの取得を必要に応じて行う
    private func requestIDFAMessageIfNeeded() async {
        let params = RequestParameters()

        #if DEBUG
        // デバッグ時は同意状態をリセットして毎回フォームを表示できるようにする
        ConsentInformation.shared.reset()
        let debug = DebugSettings()
        debug.testDeviceIdentifiers = ["SIMULATOR"]
        params.debugSettings = debug
        #endif

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
        } catch {
            return
        }

        await presentFormIfRequired()
    }

    /// 同意フォームを表示する
    private func presentFormIfRequired() async {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first?.rootViewController
        else { return }

        await withCheckedContinuation { cont in
            ConsentForm.loadAndPresentIfRequired(from: root) { _ in
                cont.resume()
            }
        }
    }
}
