//
//  AdMobBanner.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/01.
//

import GoogleMobileAds
import AppTrackingTransparency

/// AdMobバナー広告の設定とリクエスト生成を担うモデル
final class AdMobBanner {
    /// 利用する広告ユニットID
    let adUnitID: String = {
        Bundle.main.object(forInfoDictionaryKey: "GADBannerIdentifier") as? String ?? "ca-app-pub-3940256099942544/2934735716"
    }()

    /// 広告リクエストを生成する
    func createAdRequest(allowPersonalizedAds: Bool) -> Request {
        let request = Request()

        if !allowPersonalizedAds {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        return request
    }

    /// トラッキング許可の有無
    var isTrackingAuthorized: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .authorized
    }
}
