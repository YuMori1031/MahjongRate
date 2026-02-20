//
//  EditGameResultView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseFirestore

/// 対局結果を編集する画面
struct EditGameResultView: View {

    /// 対象の対局記録ID
    let recordID: String
    /// 対象の結果ID
    let resultID: String
    /// 初期表示に使う結果
    let initial: GameResult
    /// レート選択肢
    let rateOptions: [Double]
    /// 原点選択肢
    let basePointsOptions: [Int]

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 入力中のタイトル
    @State private var title: String
    /// 入力中の日付
    @State private var date: Date
    /// 入力中のレート
    @State private var rate: Double
    /// 入力中の原点
    @State private var basePoints: Int
    /// 選択中のプレイヤーID一覧
    @State private var selectedPlayerIDs: [String]

    /// 登録済みプレイヤー一覧
    @State private var allPlayers: [Player] = []
    /// プレイヤー購読リスナー
    @State private var playersListener: ListenerRegistration? = nil

    /// プレイヤー選択シート表示フラグ
    @State private var isShowingPlayerPicker = false
    /// 保存処理中フラグ
    @State private var isSaving = false
    /// アラート表示フラグ
    @State private var showAlert = false
    /// アラートメッセージ
    @State private var alertMessage = ""

    /// プレビュー実行中かどうか
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// 初期値を注入して初期化する
    init(
        recordID: String,
        resultID: String,
        initial: GameResult,
        rateOptions: [Double],
        basePointsOptions: [Int]
    ) {
        self.recordID = recordID
        self.resultID = resultID
        self.initial = initial
        self.rateOptions = rateOptions
        self.basePointsOptions = basePointsOptions

        _title = State(initialValue: initial.title)
        _date = State(initialValue: initial.date)
        _rate = State(initialValue: initial.rate)
        _basePoints = State(initialValue: initial.basePoints)
        _selectedPlayerIDs = State(initialValue: initial.playerIDs)
    }

    /// トリム済みタイトル
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 選択中プレイヤー一覧
    private var selectedPlayers: [Player] {
        var dict: [String: Player] = [:]
        for p in allPlayers {
            guard let id = p.id else { continue }
            dict[id] = p
        }
        return selectedPlayerIDs.compactMap { dict[$0] }
    }

    /// 保存可能かどうか
    private var canSave: Bool {
        guard !isSaving else { return false }
        guard !trimmedTitle.isEmpty else { return false }
        guard !selectedPlayerIDs.isEmpty else { return false }
        guard selectedPlayerIDs.count <= 10 else { return false }
        return true
    }

    /// 画面の本体
    var body: some View {
        ZStack {
            Form {
                Section(header: Text("対局情報")) {

                    HStack {
                        Text("タイトル")

                        Spacer()

                        TextField("例：半荘1回目", text: $title)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("対局日", selection: $date, displayedComponents: .date)

                    Picker("レート", selection: $rate) {
                        ForEach(rateOptions, id: \.self) { r in
                            Text("\(Int(r))ポイント").tag(r)
                        }
                    }

                    Picker("原点", selection: $basePoints) {
                        ForEach(basePointsOptions, id: \.self) { p in
                            Text("\(p)点").tag(p)
                        }
                    }
                }

                Section(header: Text("プレイヤー")) {
                    if selectedPlayerIDs.isEmpty {
                        Text("プレイヤーが未選択です。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(selectedPlayers) { p in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.secondary)
                                Text(p.name)
                                Spacer()
                            }
                        }
                        .deleteDisabled(true)
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

                    if selectedPlayerIDs.count > 5 {
                        Text("プレイヤーは最大10人までです。余分なプレイヤーを削除してください。")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Color.clear
                        .frame(height: 60)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("対局記録を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
                    .disabled(isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    Task { await saveTapped() }
                } label: {
                    Text(isSaving ? "保存中…" : "保存")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .disabled(!canSave)
                .foregroundColor(.white)
                .background(canSave ? Color.blue : Color.gray.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
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
            guard !isPreview else { return }
            startPlayersListening()
        }
        .onDisappear {
            playersListener?.remove()
            playersListener = nil
        }
        .alert("エラー", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
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
    @MainActor
    private func saveTapped() async {
        guard canSave else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let db = Firestore.firestore()

            try await db.collection("gameRecords")
                .document(recordID)
                .collection("gameResults")
                .document(resultID)
                .updateData([
                    "title": trimmedTitle,
                    "date": Timestamp(date: date),
                    "rate": rate,
                    "basePoints": basePoints,
                    "playerIDs": selectedPlayerIDs,
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            try await db.collection("gameRecords")
                .document(recordID)
                .updateData([
                    "updatedAt": FieldValue.serverTimestamp()
                ])

            dismiss()
        } catch {
            alertMessage = "保存に失敗しました: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    let recordID = "record123"
    let resultID = "session1"

    let initial = GameResult(
        id: resultID,
        gameRecordID: recordID,
        date: Date(),
        title: "半荘1回目",
        rate: 50.0,
        basePoints: 25000,
        playerIDs: ["p1", "p2", "p3", "p4"],
        updatedAt: nil
    )

    return NavigationStack {
        EditGameResultView(
            recordID: recordID,
            resultID: resultID,
            initial: initial,
            rateOptions: [10.0, 20.0, 50.0, 100.0],
            basePointsOptions: [25000, 30000, 35000]
        )
    }
}
