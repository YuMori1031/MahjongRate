//
//  PasswordResetView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI
import FirebaseAuth

/// パスワード再設定メールを送る画面
struct PasswordResetView: View {
    /// 入力中のメールアドレス
    @State private var email: String = ""
    /// 送信処理中かどうか
    @State private var isSending = false

    /// アラートの表示状態
    @State private var isShowingAlert = false
    /// アラートのタイトル
    @State private var alertTitle: String = ""
    /// アラートの本文
    @State private var alertMessage: String = ""

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// パスワードリセット画面
    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ユーザー情報")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Divider()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("メールアドレス", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            Button {
                sendPasswordReset()
            } label: {
                Text("送信")
                    .font(.headline)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(canSend ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(24)
                    .shadow(radius: canSend ? 3 : 0)
            }
            .disabled(!canSend || isSending)

            Spacer()
        }
        .padding()
        .navigationTitle("パスワードリセット")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSending)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK") {
                if alertTitle == "再設定メール送信" {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .loadingOverlay(isPresented: isSending, message: "送信中…")
    }

    /// 送信ボタンを有効にできるかどうか
    private var canSend: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 再設定メールを送信する
    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard EmailValidator.isValid(trimmedEmail) else {
            alertTitle = "エラー"
            alertMessage = "メールアドレスの形式が正しくありません。"
            isShowingAlert = true
            return
        }

        isSending = true
        Auth.auth().sendPasswordReset(withEmail: trimmedEmail) { error in
            defer { isSending = false }

            if let error = error {
                alertTitle = "エラー"
                alertMessage = AuthErrorMapper.message(for: error)
            } else {
                alertTitle = "再設定メール送信"
                alertMessage = "パスワード再設定用のメールを送信しました。"
            }
            isShowingAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        PasswordResetView()
    }
}
