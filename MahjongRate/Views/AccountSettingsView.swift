//
//  AccountSettingsView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI

/// アカウント設定画面を表示するView
struct AccountSettingsView: View {

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthViewModel.shared

    /// 画面の本体
    var body: some View {
        Form {
            Section("メールアドレス") {
                NavigationLink {
                    ChangeEmailView()
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                        Text("メールアドレスを変更")
                    }
                }
            }

            Section("パスワード") {
                NavigationLink {
                    ChangePasswordView()
                } label: {
                    HStack {
                        Image(systemName: "key")
                        Text("パスワードを変更")
                    }
                }
            }

            Section {
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("アカウントを削除")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("アカウント設定")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.user == nil) { _, isSignedOut in
            if isSignedOut {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView()
    }
}
