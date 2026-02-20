//
//  DeleteAccountView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

/// アカウント削除画面
struct DeleteAccountView: View {

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// ストレージViewModel
    @EnvironmentObject private var storage: StorageViewModel

    /// 入力中のパスワード
    @State private var password: String = ""
    /// 削除処理中フラグ
    @State private var isDeleting: Bool = false
    /// 確認ダイアログ表示フラグ
    @State private var showConfirm: Bool = false
    /// アラート表示フラグ
    @State private var showAlert: Bool = false
    /// アラートメッセージ
    @State private var alertMessage: String = ""

    /// 削除可能かどうか
    private var canSubmit: Bool {
        !password.isEmpty && !isDeleting
    }

    /// 画面の本体
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("アカウントを削除すると、元に戻せません。")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text("削除するには、セキュリティのためパスワードを再入力してください。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("再認証") {
                SecureField("パスワード", text: $password)
                    .textContentType(.password)
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Text(isDeleting ? "削除中…" : "アカウントを削除")
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("アカウントを削除")
        .navigationBarTitleDisplayMode(.inline)
        .alert("本当にアカウントを削除しますか？", isPresented: $showConfirm) {
            Button("削除する", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("エラー", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    /// アカウントを削除する
    @MainActor
    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await AuthViewModel.shared.deleteAccount(password: password)
        } catch {
            alertMessage = friendlyMessage(error)
            showAlert = true
        }
    }

    /// エラー内容をユーザー向けに整形する
    private func friendlyMessage(_ error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == AuthErrorDomain || nsError.domain == "FIRAuthErrorDomain" {
            switch nsError.code {
            case 17004:
                return "パスワードが違います。"

            case 17009:
                return "パスワードが違います。"

            case 17005:
                return "このアカウントは無効化されています。"

            case 17010:
                return "試行回数が多すぎます。しばらく待ってから再度お試しください。"

            case 17014:
                return "再ログインが必要です。いったんログアウト→ログイン後に再度お試しください。"

            default:
                return "削除に失敗しました。"
            }
        }
        return "削除に失敗しました。"
    }
}

#Preview {
    DeleteAccountView()
}
