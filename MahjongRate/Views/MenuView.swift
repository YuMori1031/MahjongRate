//
//  MenuView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI

/// サイドメニュー画面
struct MenuView: View {
    /// メニューの開閉状態
    @Binding var isOpen: Bool
    /// プロフィール画面への遷移フラグ
    @Binding var navigateToProfile: Bool
    /// アカウント設定画面への遷移フラグ
    @Binding var navigateToAccountSettings: Bool

    /// 認証処理を担当するViewModel
    @ObservedObject private var auth = AuthViewModel.shared
    /// ログアウト確認の表示状態
    @State private var showingLogoutAlert = false
    /// 利用規約の表示状態
    @State private var showingTerms = false

    /// エラーアラートの表示状態
    @State private var isShowingErrorAlert = false
    /// エラーメッセージ
    @State private var errorMessage: String? = nil

    @Environment(\.openURL) private var openURL

    /// プライバシーポリシーのURL
    private let privacyPolicyURL = URL(string: "https://www.yumori.dev/privacy/mahjongrate/")

    /// 画面幅に合わせたメニュー最大幅
    private let maxWidth = UIScreen.main.bounds.width

    /// サイドメニューの表示
    var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
                .opacity(isOpen ? 0.7 : 0)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isOpen.toggle()
                    }
                }

            ZStack {
                List {
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isOpen.toggle()
                            }
                            navigateToProfile = true
                        } label: {
                            HStack {
                                Image(systemName: "person.circle")
                                Text("プロフィール")
                            }
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isOpen.toggle()
                            }
                            navigateToAccountSettings = true
                        } label: {
                            HStack {
                                Image(systemName: "gearshape")
                                Text("アカウント設定")
                            }
                        }
                    }

                    Section {
                        Button {
                            showingTerms = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("利用規約")
                            }
                        }

                        Button {
                            if let url = privacyPolicyURL {
                                openURL(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "hand.raised")
                                Text("プライバシーポリシー")
                            }
                        }
                    }

                    Section {
                        Button {
                            showingLogoutAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.backward.circle")
                                Text("ログアウト")
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .padding(.trailing, maxWidth / 4)
        .offset(x: isOpen ? 0 : -maxWidth)
        .sheet(isPresented: $showingTerms) {
            NavigationStack {
                TermsView()
            }
        }
        .alert("ログアウトしますか？", isPresented: $showingLogoutAlert) {
            Button("ログアウト", role: .destructive) {
                do {
                    try auth.signOut()

                    withAnimation(.easeInOut(duration: 0.3)) {
                        isOpen = false
                    }
                } catch {
                    errorMessage = AuthErrorMapper.message(for: error)
                    isShowingErrorAlert = true
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("現在のアカウントからログアウトします。")
        }
        .alert("エラー", isPresented: $isShowingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "エラーが発生しました。")
        }
    }
}

#Preview {
    MenuView(
        isOpen: .constant(true),
        navigateToProfile: .constant(false),
        navigateToAccountSettings: .constant(false)
    )
}
