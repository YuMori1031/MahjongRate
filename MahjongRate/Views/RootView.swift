//
//  RootView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI

/// アプリのルート画面
struct RootView: View {
    /// 認証状態を監視するViewModel
    @ObservedObject private var auth = AuthViewModel.shared
    /// データストアを注入する環境オブジェクト
    @EnvironmentObject private var storage: StorageViewModel
    /// 広告制御の環境オブジェクト
    @EnvironmentObject private var admob: AdmobController

    /// NavigationStack のパス
    @State private var path: [GameRecord] = []
    /// サイドメニューの表示状態
    @State private var isMenuOpen = false
    /// プロフィール画面への遷移フラグ
    @State private var navigateToProfile = false
    /// アカウント設定画面への遷移フラグ
    @State private var navigateToAccountSettings = false

    /// アプリ全体のルート構成
    var body: some View {
        let hideAdsForScreenshot = false
        VStack(spacing: 0) {
            if !hideAdsForScreenshot && admob.canShowAds && auth.user != nil {
                AdMobBannerView()
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .background(Color(.systemBackground))
            }

            ZStack(alignment: .leading) {
                NavigationStack(path: $path) {
                    Group {
                        if auth.user == nil {
                            LoginView()
                        } else {
                            ContentView(
                                path: $path,
                                isMenuOpen: $isMenuOpen,
                                navigateToProfile: $navigateToProfile,
                                navigateToAccountSettings: $navigateToAccountSettings
                            )
                        }
                    }
                    .navigationDestination(for: GameRecord.self) { record in
                        GameRecordDetailView(record: record)
                    }
                    .navigationDestination(isPresented: $navigateToProfile) {
                        ProfileView()
                    }
                    .navigationDestination(isPresented: $navigateToAccountSettings) {
                        AccountSettingsView()
                    }
                }
                .allowsHitTesting(!isMenuOpen)
                if isMenuOpen {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.22)) { isMenuOpen = false } }
                        .zIndex(1)
                        .transition(.opacity)

                    MenuView(
                        isOpen: $isMenuOpen,
                        navigateToProfile: $navigateToProfile,
                        navigateToAccountSettings: $navigateToAccountSettings
                    )
                    .ignoresSafeArea()
                    .zIndex(2)
                    .transition(.move(edge: .leading))
                }
            }
        }
        .onChange(of: auth.user == nil) { _, isSignedOut in
            if isSignedOut {
                path.removeAll()
                navigateToProfile = false
                navigateToAccountSettings = false
                isMenuOpen = false
            }
        }
    }
}

#Preview {
    let admobController = AdmobController()
    admobController.canShowAds = true

    return RootView()
        .environmentObject(admobController)
}
