//
//  AddGameSessionView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseFirestore

/// 対局セッションを追加する画面
struct AddGameSessionView: View {

    /// 対象の対局記録ID
    let recordID: String
    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss
    /// ストレージViewModel
    @ObservedObject private var vm = StorageViewModel.shared

    /// 入力中のタイトル
    @State private var title: String = ""
    /// 入力中の日付
    @State private var date: Date = Date()
    /// 入力中のレート
    @State private var rate: Double = 50.0
    /// 入力中の原点
    @State private var basePoints: Int = 25000

    /// 選択中のプレイヤーID一覧
    @State private var selectedPlayerIDs: [String] = []

    /// 登録済みプレイヤー一覧
    @State private var allPlayers: [Player] = []
    /// プレイヤー購読リスナー
    @State private var playersListener: ListenerRegistration? = nil

    /// アラート表示フラグ
    @State private var showAlert = false
    /// アラートメッセージ
    @State private var alertMessage = ""
    /// 上限到達アラート表示フラグ
    @State private var showLimitAlert = false
    /// プレイヤー選択シート表示フラグ
    @State private var isShowingPlayerPicker = false

    /// レート選択肢
    private let rateOptions: [Double] = [10.0, 20.0, 50.0, 100.0]
    /// 原点選択肢
    private let pointsOptions: [Int] = [25000, 30000, 35000]

    /// トリム済みタイトル
    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 保存可能かどうか
    private var canSave: Bool {
        !trimmedTitle.isEmpty && !selectedPlayerIDs.isEmpty && !hasReachedSessionLimit
    }

    /// 対局結果数の上限に達しているか
    private var hasReachedSessionLimit: Bool {
        vm.gameResults.count >= 100
    }

    /// 選択中プレイヤー一覧
    private var selectedPlayers: [Player] {
        var dict: [String: Player] = [:]
        for p in allPlayers {
            guard let id = p.id else { continue }
            dict[id] = p
        }
        return selectedPlayerIDs.compactMap { dict[$0] }
    }

    /// 画面の本体
    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section(header: Text("対局情報")) {
                        TextField("タイトル", text: $title)

                        HStack {
                            Image(systemName: "calendar").foregroundColor(.blue)
                            DatePicker("日付", selection: $date, displayedComponents: .date)
                        }

                        HStack {
                            Image(systemName: "dollarsign.circle").foregroundColor(.green)
                            Picker("レート", selection: $rate) {
                                ForEach(rateOptions, id: \.self) { r in
                                    Text("\(Int(r))ポイント").tag(r)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                        }

                        HStack {
                            Image(systemName: "target").foregroundColor(.orange)
                            Picker("原点", selection: $basePoints) {
                                ForEach(pointsOptions, id: \.self) { p in
                                    Text("\(p)点").tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Section(header: Text("プレイヤー")) {
                        if selectedPlayerIDs.isEmpty {
                            Text("プレイヤーが未選択です。下のボタンから選択してください。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(selectedPlayerIDs, id: \.self) { pid in
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.secondary)
                                    Text(playerName(for: pid))
                                    Spacer()
                                }
                            }
                            .onDelete(perform: deleteSelectedPlayers)
                        }

                        Button {
                            isShowingPlayerPicker = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                Text("プレイヤーを選択・追加")
                                Spacer()
                            }
                        }
                    }

                    if hasReachedSessionLimit {
                        Section {
                            Text("対局結果は最大100件まで登録できます。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationTitle("対局記録を追加")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                }
                .sheet(isPresented: $isShowingPlayerPicker) {
                    NavigationStack {
                        PlayerPickerView(
                            recordID: recordID,
                            selectedIDs: $selectedPlayerIDs
                        )
                    }
                }
                .task {
                    startPlayersListening()
                }
                .onDisappear {
                    playersListener?.remove()
                    playersListener = nil
                }

                Button("保存") {
                    saveTapped()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .background(canSave ? Color.blue : Color.gray.opacity(0.3))
                .cornerRadius(8)
                .padding()
                .disabled(!canSave)
                .alert("エラー", isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(alertMessage)
                }
                .alert("上限に達しました", isPresented: $showLimitAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("対局結果は最大100件まで登録できます。")
                }
            }
        }
    }

    /// 選択中プレイヤーを削除する
    private func deleteSelectedPlayers(at offsets: IndexSet) {
        selectedPlayerIDs.remove(atOffsets: offsets)
    }

    /// プレイヤー名を取得する
    private func playerName(for id: String) -> String {
        allPlayers.first(where: { $0.id == id })?.name ?? id
    }

    /// プレイヤー一覧の購読を開始する
    private func startPlayersListening() {
        guard playersListener == nil else { return }
        let storage = FirestoreStorage()
        playersListener = storage.subscribePlayers(for: recordID) { list in
            self.allPlayers = list
        }
    }

    /// 保存処理を実行する
    private func saveTapped() {
        guard !hasReachedSessionLimit else {
            showLimitAlert = true
            return
        }
        guard !trimmedTitle.isEmpty else {
            alertMessage = "タイトルを入力してください。"
            showAlert = true
            return
        }
        guard !selectedPlayerIDs.isEmpty else {
            alertMessage = "プレイヤーを1人以上選択してください。"
            showAlert = true
            return
        }

        vm.addGameResult(
            date: date,
            title: trimmedTitle,
            rate: rate,
            basePoints: basePoints,
            recordID: recordID,
            players: selectedPlayers
        )

        dismiss()
    }
}

#Preview {
    NavigationStack {
        AddGameSessionView(recordID: "record123")
    }
}
