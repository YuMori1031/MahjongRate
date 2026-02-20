//
//  RegistrationView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI

/// 新規登録画面
struct RegistrationView: View {
    /// 入力中のユーザー名
    @State private var username: String = ""
    /// 入力中のメールアドレス
    @State private var email: String = ""
    /// 入力中のパスワード
    @State private var password: String = ""

    /// 登録処理中かどうか
    @State private var isSaving = false

    /// アラートの表示状態
    @State private var isShowingAlert = false
    /// アラートのタイトル
    @State private var alertTitle: String = ""
    /// アラートの本文
    @State private var alertMessage: String = ""

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss
    /// 認証処理を担当するViewModel
    @ObservedObject private var auth = AuthViewModel.shared

    /// 新規登録画面
    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ユーザー情報")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Divider()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 16) {
                TextField("ユーザー名", text: $username)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                TextField("メールアドレス", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                SecureField("パスワード（6文字以上）", text: $password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            HStack {
                Spacer()
                Button {
                    registerAndSendVerification()
                } label: {
                    Text("登録")
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(canRegister ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(24)
                        .shadow(radius: canRegister ? 3 : 0)
                }
                .disabled(!canRegister || isSaving)
                Spacer()
            }

            Spacer()
        }
        .padding()
        .navigationTitle("新規登録")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK") {
                if alertTitle == "認証メールを送信しました" {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .loadingOverlay(isPresented: isSaving, message: "登録中…")
    }

    /// 登録ボタンを有効にできるかどうか
    private var canRegister: Bool {
        !username.isEmpty && !email.isEmpty && !password.isEmpty
    }

    /// 登録処理と認証メール送信を行う
    private func registerAndSendVerification() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard EmailValidator.isValid(trimmedEmail) else {
            alertTitle = "エラー"
            alertMessage = "メールアドレスの形式が正しくありません。"
            isShowingAlert = true
            return
        }

        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await auth.signUp(
                    email: trimmedEmail,
                    password: password,
                    username: username
                )

                alertTitle = "認証メールを送信しました"
                alertMessage = """
                \(username) さん、
                登録されたメールアドレス宛に認証メールを送信しました。
                メール内のリンクをクリックして登録を完了してください。
                """
                isShowingAlert = true
            } catch {
                alertTitle = "エラー"
                alertMessage = AuthErrorMapper.message(for: error)
                isShowingAlert = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        RegistrationView()
    }
}
