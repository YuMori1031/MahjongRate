//
//  LoginView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI
import FirebaseAuth

/// ログイン画面
struct LoginView: View {
    /// 入力中のメールアドレス
    @State private var email: String = ""
    /// 入力中のパスワード
    @State private var password: String = ""
    /// 新規登録画面の表示状態
    @State private var showingRegistration = false
    /// パスワード再設定画面の表示状態
    @State private var showingPasswordReset = false
    /// 利用規約の表示状態
    @State private var showingTerms = false
    /// プライバシーポリシーのURL
    private let privacyPolicyURL = URL(string: "https://www.yumori.dev/privacy/mahjongrate/")

    /// エラーメッセージ
    @State private var alertMessage: String? = nil
    /// エラーダイアログの表示状態
    @State private var isShowingAlert = false

    /// ログイン処理中かどうか
    @State private var isSigningIn = false

    /// 認証処理を担当するViewModel
    @ObservedObject private var auth = AuthViewModel.shared

    @Environment(\.openURL) private var openURL

    /// ログインフォーム
    var body: some View {
        VStack(spacing: 24) {
            Text("雀レート")
                .font(.largeTitle)
                .bold()

            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            SecureField("パスワード", text: $password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            Button("ログイン") {
                signIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || isSigningIn)

            Button {
                showingRegistration = true
            } label: {
                Text("アカウントの新規登録はこちら")
                    .font(.footnote)
                    .underline()
                    .foregroundColor(.blue)
            }

            Button {
                showingPasswordReset = true
            } label: {
                Text("パスワードを忘れた場合はこちら")
                    .font(.footnote)
                    .underline()
                    .foregroundColor(.blue)
            }

            HStack(spacing: 12) {
                Button {
                    showingTerms = true
                } label: {
                    Text("利用規約")
                        .font(.footnote)
                        .underline()
                        .foregroundColor(.blue)
                }

                Text("|")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button {
                    if let url = privacyPolicyURL {
                        openURL(url)
                    }
                } label: {
                    Text("プライバシーポリシー")
                        .font(.footnote)
                        .underline()
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .loadingOverlay(isPresented: isSigningIn, message: "ログイン中…")
        .sheet(isPresented: $showingRegistration) {
            NavigationStack {
                RegistrationView()
            }
        }
        .sheet(isPresented: $showingPasswordReset) {
            NavigationStack {
                PasswordResetView()
            }
        }
        .sheet(isPresented: $showingTerms) {
            NavigationStack {
                TermsView()
            }
        }
        .alert("エラー", isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "エラーが発生しました。")
        }
    }

    /// 入力内容でログインを実行する
    private func signIn() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if !EmailValidator.isValid(trimmed) {
            alertMessage = "メールアドレスの形式が正しくありません。"
            isShowingAlert = true
            return
        }

        Task {
            isSigningIn = true
            defer { isSigningIn = false }

            do {
                try await auth.signIn(email: trimmed, password: password)
            } catch {
                alertMessage = AuthErrorMapper.message(for: error)
                isShowingAlert = true
            }
        }
    }
}

#Preview {
    LoginView()
}
