//
//  PlayerListView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/09.
//

import SwiftUI
import FirebaseFirestore

/// プレイヤー一覧の追加・削除を行う画面
struct PlayerListView: View {
    /// 対象の記録ID
    let recordID: String

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 全プレイヤーの一覧
    @State private var allPlayers: [Player] = []
    /// プレイヤー購読のリスナー
    @State private var listener: ListenerRegistration? = nil

    /// 新規プレイヤー名の入力値
    @State private var newPlayerName: String = ""
    /// 追加処理中かどうか
    @State private var isSavingAdd = false

    /// エラー表示の状態
    @State private var showAlert = false
    /// エラーメッセージ
    @State private var alertMessage = ""
    /// 削除対象のプレイヤー
    @State private var pendingDeletePlayer: Player? = nil
    /// 削除確認アラート表示フラグ
    @State private var isShowingDeleteConfirm = false

    /// Firestore の読み書きを行う窓口
    private let storage = FirestoreStorage()

    /// プレビュー実行中かどうか
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// 追加入力のトリム済み文字列
    private var trimmedNewName: String {
        newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 追加できるかどうか
    private var canAddPlayer: Bool {
        !trimmedNewName.isEmpty && !isSavingAdd && !isPreview && allPlayers.count < 10
    }

    /// 画面の本体
    var body: some View {
        List {
            Section(header: Text("新規プレイヤーを追加")) {
                HStack {
                    TextField("名前", text: $newPlayerName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button("追加") {
                        Task { await addNewPlayer() }
                    }
                    .disabled(!canAddPlayer)
                }

                if allPlayers.count >= 10 {
                    Text("プレイヤーは最大10人まで登録できます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("登録プレイヤー")) {
                if allPlayers.isEmpty {
                    Text("プレイヤーがまだ登録されていません。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(allPlayers) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingDeletePlayer = p
                                DispatchQueue.main.async {
                                    isShowingDeleteConfirm = true
                                }
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                            .tint(.red)
                            .disabled(isPreview)
                        }
                    }
                }
            }
        }
        .navigationTitle("プレイヤー一覧")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .task {
            if isPreview {
                allPlayers = PreviewData.players
            } else {
                startListening()
            }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .alert("エラー", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("このプレイヤーを削除しますか？", isPresented: $isShowingDeleteConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let player = pendingDeletePlayer {
                    Task { await deletePlayer(player) }
                }
            }
        } message: {
            if let player = pendingDeletePlayer {
                Text("「\(player.name)」を削除します。")
            }
        }
    }


    /// プレイヤー一覧の購読を開始する
    private func startListening() {
        guard listener == nil else { return }
        listener = storage.subscribePlayers(for: recordID) { list in
            self.allPlayers = list
        }
    }

    /// 新規プレイヤーを追加する
    private func addNewPlayer() async {
        guard !isPreview else { return }

        let name = trimmedNewName
        guard !name.isEmpty else { return }
        guard allPlayers.count < 10 else {
            alertMessage = "プレイヤーは最大10人まで登録できます。"
            showAlert = true
            return
        }

        isSavingAdd = true
        defer { isSavingAdd = false }

        do {
            if allPlayers.contains(where: { $0.name == name }) {
                alertMessage = "同じ名前のプレイヤーがすでに存在します。"
                showAlert = true
                return
            }

            _ = try await storage.addPlayer(to: recordID, name: name)
            newPlayerName = ""
        } catch {
            alertMessage = "追加に失敗しました: \(error.localizedDescription)"
            showAlert = true
        }
    }

    /// 既存プレイヤーを削除する
    private func deletePlayer(_ p: Player) async {
        guard !isPreview else { return }
        guard let id = p.id else { return }
        do {
            if try await storage.hasScores(for: recordID, playerID: id) {
                alertMessage = "このプレイヤーはスコアが登録されているため削除できません。関連する対局結果を削除してください。"
                showAlert = true
                return
            }
            try await storage.deletePlayer(in: recordID, playerID: id)
        } catch {
            alertMessage = "削除に失敗しました。しばらくしてから再試行してください。"
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        PlayerListView(recordID: "preview-record")
    }
}
