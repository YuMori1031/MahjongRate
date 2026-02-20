//
//  PlayerPickerView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseFirestore

/// プレイヤー選択と追加を行う画面
struct PlayerPickerView: View {
    /// 対象の記録ID
    let recordID: String
    /// 選択中のプレイヤーID
    @Binding var selectedIDs: [String]

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 全プレイヤーの一覧
    @State private var allPlayers: [Player] = []
    /// プレイヤー購読のリスナー
    @State private var listener: ListenerRegistration? = nil

    /// チェック中のプレイヤーID
    @State private var checkedIDs: Set<String> = []

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

    /// 追加入力のトリム済み文字列
    private var trimmedNewName: String {
        newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 追加できるかどうか
    private var canAddPlayer: Bool {
        !trimmedNewName.isEmpty && !isSavingAdd && allPlayers.count < 10
    }

    /// 選択済みプレイヤーの一覧
    private var checkedPlayers: [Player] {
        allPlayers.filter { p in
            guard let id = p.id else { return false }
            return checkedIDs.contains(id)
        }
    }

    /// プレイヤー選択画面
    var body: some View {
        VStack(spacing: 0) {
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

                Section(header: Text("登録プレイヤー（タップで選択）")) {
                    if allPlayers.isEmpty {
                        Text("プレイヤーがまだ登録されていません。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(allPlayers) { p in
                            HStack {
                                Text(p.name)
                                Spacer()
                                if let id = p.id, checkedIDs.contains(id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleCheck(p)
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
                            }
                        }
                    }
                }

            }

            Button {
                commitSelectionAndClose()
            } label: {
                Text("保存（\(min(checkedPlayers.count, 10))人を反映）")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(checkedPlayers.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .cornerRadius(10)
                    .padding()
            }
            .disabled(checkedPlayers.isEmpty)
        }
        .navigationTitle("プレイヤー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .task {
            checkedIDs = Set(selectedIDs)
            startListening()
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
            Task { @MainActor in
                self.allPlayers = list
            }
        }
    }

    /// 選択状態を切り替える
    private func toggleCheck(_ p: Player) {
        guard let id = p.id else { return }
        if checkedIDs.contains(id) {
            checkedIDs.remove(id)
        } else {
            checkedIDs.insert(id)
        }
    }

    /// 選択内容を確定して閉じる
    private func commitSelectionAndClose() {
        let ids = checkedPlayers.compactMap { $0.id }
        if ids.count > 10 {
            alertMessage = "選択できるのは最大10人までです。10人以内にしてください。"
            showAlert = true
            return
        }
        selectedIDs = ids
        dismiss()
    }

    /// 新規プレイヤーを追加する
    private func addNewPlayer() async {
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
        guard let id = p.id else { return }
        do {
            if try await storage.hasScores(for: recordID, playerID: id) {
                alertMessage = "このプレイヤーはスコアが登録されているため削除できません。関連する対局結果を削除してください。"
                showAlert = true
                return
            }
            try await storage.deletePlayer(in: recordID, playerID: id)
            checkedIDs.remove(id)
        } catch {
            alertMessage = "削除に失敗しました。しばらくしてから再試行してください。"
            showAlert = true
        }
    }
}

#Preview {
    @Previewable @State var selectedIDs: [String] = ["p1", "p3"]

    return NavigationStack {
        PlayerPickerView(
            recordID: "preview-record",
            selectedIDs: $selectedIDs
        )
    }
}
