//
//  ChangePasswordView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI

/// パスワード変更画面
struct ChangePasswordView: View {

    /// 認証ViewModel
    @ObservedObject private var auth = AuthViewModel.shared

    /// 入力中の現在パスワード
    @State private var currentPassword: String = ""
    /// 入力中の新パスワード
    @State private var newPassword: String = ""
    /// 入力中の確認パスワード
    @State private var confirmPassword: String = ""

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
                Text("現在のパスワード")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("現在のパスワード", text: $currentPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("新しいパスワード")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("新しいパスワード（6文字以上）", text: $newPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("新しいパスワード（確認）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                SecureField("新しいパスワードを再入力", text: $confirmPassword)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !confirmPassword.isEmpty && confirmPassword != newPassword {
                    Text("新しいパスワードと確認用パスワードが一致していません。")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                if !newPassword.isEmpty && newPassword == currentPassword {
                    Text("現在のパスワードと同じです。別のパスワードを設定してください。")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            HStack {
                Spacer()
                Button {
                    changePassword()
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
        .navigationTitle("パスワードを変更")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .loadingOverlay(isPresented: isSaving, message: "更新中…")
    }

    /// 更新可能かどうか
    private var canSave: Bool {
        let trimmedCurrent = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        return !trimmedCurrent.isEmpty &&
               !trimmedNew.isEmpty &&
               trimmedNew.count >= 6 &&
               trimmedNew == confirmPassword &&
               trimmedNew != trimmedCurrent &&
               !isSaving
    }

    /// パスワード変更を実行する
    private func changePassword() {
        let trimmedCurrent = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedCurrent.isEmpty, !trimmedNew.isEmpty else { return }

        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await auth.changePassword(
                    currentPassword: trimmedCurrent,
                    newPassword: trimmedNew
                )

                currentPassword = ""
                newPassword = ""
                confirmPassword = ""

                alertTitle = "パスワードを変更しました"
                alertMessage = "新しいパスワードでログインできるようになりました。"
                isShowingAlert = true

            } catch {
                alertTitle = "エラー"
                alertMessage = AuthErrorMapper.message(for: error)
                isShowingAlert = true
            }
        }
    }
}

#Preview("ChangePasswordView") {
    NavigationStack {
        ChangePasswordView()
    }
}
