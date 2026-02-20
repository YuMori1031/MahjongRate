//
//  ChangeEmailView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseAuth

/// メールアドレス変更画面
struct ChangeEmailView: View {

    /// 認証ViewModel
    @ObservedObject private var auth = AuthViewModel.shared

    /// 入力中の新メールアドレス
    @State private var newEmail: String = ""
    /// 入力中の現在パスワード
    @State private var currentPassword: String = ""

    /// 更新処理中フラグ
    @State private var isSaving = false

    /// アラート表示フラグ
    @State private var isShowingAlert = false
    /// アラートタイトル
    @State private var alertTitle: String = ""
    /// アラートメッセージ
    @State private var alertMessage: String = ""

    /// 画面の本体
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            VStack(alignment: .leading, spacing: 8) {
                Text("現在のメールアドレス")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(auth.user?.email ?? "未設定")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("新しいメールアドレス")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("メールアドレス", text: $newEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("確認用パスワード")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("現在のパスワード", text: $currentPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            HStack {
                Spacer()
                Button {
                    changeEmail()
                } label: {
                    Text("更新")
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(canSave ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(24)
                        .shadow(radius: canSave ? 3 : 0)
                }
                .disabled(!canSave)
                Spacer()
            }

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .navigationTitle("メールアドレスを変更")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK") {
                if alertTitle == "確認メールを送信しました" {
                    Task { @MainActor in
                        StorageViewModel.shared.reset()

                        do {
                            try AuthViewModel.shared.signOut()
                        } catch {
                            print("❌ signOut error:", error)
                        }
                    }
                }
            }
        } message: {
            Text(alertMessage)
        }
        .loadingOverlay(isPresented: isSaving, message: "更新中…")
    }

    /// 更新可能かどうか
    private var canSave: Bool {
        !newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !currentPassword.isEmpty &&
        !isSaving
    }

    /// メールアドレス変更を実行する
    private func changeEmail() {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard EmailValidator.isValid(trimmed) else {
            alertTitle = "エラー"
            alertMessage = "メールアドレスの形式が正しくありません。"
            isShowingAlert = true
            return
        }

        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await auth.requestEmailUpdate(
                    to: trimmed,
                    currentPassword: currentPassword
                )

                alertTitle = "確認メールを送信しました"
                alertMessage = """
                               新しいメールアドレス宛に確認メールを送信しました。
                               メール内のリンクをクリックすると変更が完了します。

                               メール認証後は新しいメールアドレスで
                               再度ログインしてください。
                               """
                isShowingAlert = true

                currentPassword = ""

            } catch {
                alertTitle = "エラー"
                alertMessage = AuthErrorMapper.message(for: error)
                isShowingAlert = true
            }
        }
    }
}

#Preview("ChangeEmailView") {
    NavigationStack {
        ChangeEmailView()
    }
}
