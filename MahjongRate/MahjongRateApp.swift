//
//  MahjongRateApp.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI
import FirebaseCore

/// アプリのエントリポイント
@main
struct MahjongRateApp: App {
    /// 認証状態の監視を行うViewModel
    @ObservedObject private var auth = AuthViewModel.shared
    /// データストアを管理するViewModel
    @StateObject private var storage = StorageViewModel.shared
    /// 広告制御を担当するコントローラ
    @StateObject private var admob = AdmobController()

    /// Firebase設定と初期化を行う
    init() {
        #if DEBUG
        let plistName = "GoogleService-Info-Test"
        print("🏷 [ENV] Running in DEV (Debug) configuration")
        #else
        let plistName = "GoogleService-Info-Prod"
        print("🏷 [ENV] Running in PROD (Release) configuration")
        #endif

        if let filePath = Bundle.main.path(forResource: plistName, ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: filePath) {
            FirebaseApp.configure(options: options)
        } else {
            fatalError("⚠️ [ENV] \(plistName).plist not found in bundle")
        }

        AuthViewModel.shared.start()

        if let plistPath = Bundle.main.path(forResource: plistName, ofType: "plist") {
            print("📦 [ENV] Loaded plist at path:", plistPath)
        } else {
            print("⚠️ [ENV] \(plistName).plist not found in bundle")
        }

        let pid = FirebaseApp.app()?.options.projectID ?? "nil"
        print("🔑 [ENV] Firebase Project ID:", pid)
    }

    /// アプリのルートシーン
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(storage)
                .environmentObject(admob)
                .task {
                    await admob.prepare()
                }
        }
    }
}
