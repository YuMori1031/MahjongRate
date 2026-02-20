//
//  JoinGameRecordView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI

/// 招待コードで記録に参加する画面
struct JoinGameRecordView: View {
    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 記録操作を行うViewModel
    @ObservedObject private var vm = StorageViewModel.shared

    /// 入力中の招待コード
    @State private var code: String = ""
    /// 参加処理中かどうか
    @State private var isLoading = false
    /// QRスキャナーの表示状態
    @State private var showingScanner = false

    /// エラーダイアログの表示状態
    @State private var isShowingAlert = false
    /// ダイアログのタイトル
    @State private var alertTitle: String = ""
    /// ダイアログの本文
    @State private var alertMessage: String = ""
    /// アラート閉じた後に画面を閉じるかどうか
    @State private var shouldDismissOnAlert: Bool = false

    /// 招待コード入力画面
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("招待コード")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Divider()
                }

                TextField("例: ABCD2345", text: $code)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                Button {
                    showingScanner = true
                } label: {
                    Label("QRコードを読み取る", systemImage: "qrcode.viewfinder")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("招待コードを直接入力するか、QRコードを読み取って記録に参加できます。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                HStack {
                    Spacer()
                    Button {
                        join()
                    } label: {
                        Text("参加")
                            .font(.headline)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(canJoin ? Color.accentColor : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(24)
                            .shadow(radius: canJoin ? 3 : 0)
                    }
                    .disabled(!canJoin)
                    Spacer()
                }
                .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .navigationTitle("招待コードで参加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                QRCodeScannerView(
                    onScan: { scanned in
                        code = scanned
                        showingScanner = false
                    },
                    onCancel: {
                        showingScanner = false
                    }
                )
                .navigationTitle("QRコードを読み取る")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("キャンセル") {
                            showingScanner = false
                        }
                    }
                }
            }
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) {
                if shouldDismissOnAlert {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .loadingOverlay(isPresented: isLoading, message: "参加処理中…")
    }

    /// 参加ボタンを有効にできるかどうか
    private var canJoin: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    /// 招待コードで参加処理を行う
    private func join() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true

        Task {
            do {
                try await vm.joinGameRecord(byInviteCode: trimmed)

                await MainActor.run {
                    isLoading = false
                    alertTitle = "参加申請を送信しました"
                    alertMessage = "管理者の承認後に参加できます。"
                    shouldDismissOnAlert = true
                    isShowingAlert = true
                }
            } catch StorageViewModel.JoinError.notFound {
                await MainActor.run {
                    isLoading = false
                    alertTitle = "記録が見つかりません"
                    alertMessage = "招待コードを確認して、もう一度入力してください。"
                    shouldDismissOnAlert = false
                    isShowingAlert = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertTitle = "エラー"
                    alertMessage = "参加に失敗しました。時間をおいて再度お試しください。"
                    shouldDismissOnAlert = false
                    isShowingAlert = true
                }
                print("❌ joinGameRecord error:", error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        JoinGameRecordView()
    }
}
