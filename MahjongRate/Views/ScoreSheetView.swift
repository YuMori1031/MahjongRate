//
//  ScoreSheetView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseFirestore

/// 局のスコア入力を行う画面
struct ScoreSheetView: View {
    /// 対象の記録ID
    let recordID: String
    /// 対象の対局情報
    let result: GameResult
    /// 対局の参加者
    let players: [Player]
    /// 編集対象の局
    let round: GameRound?
    /// 次の局番号
    let nextRoundNumber: Int
    /// 保存完了時のコールバック
    let onSaved: () -> Void

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 入力中のスコア
    @State private var scores: [Score] = []
    /// 符号選択の状態
    @State private var signSelection: [String: Bool] = [:]
    /// 休みの状態
    @State private var isResting: [String: Bool] = [:]
    /// キーボードフォーカス対象
    @FocusState private var focusedField: String?
    /// 既存スコアを読み込んだかどうか
    @State private var didLoadExistingScores = false
    /// 既存スコアの読み込み中かどうか
    @State private var isLoadingExistingScores = false
    /// エラー表示の状態
    @State private var showAlert = false
    /// エラーメッセージ
    @State private var alertMessage = ""

    /// プレビュー実行中かどうか
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// スコア入力画面
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if isLoadingExistingScores {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("保存済みスコアを読み込み中…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(players) { player in
                            let pid = player.id ?? ""
                            if !pid.isEmpty {
                                playerRow(player: player, pid: pid)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button("保存") {
                    Task { await save() }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding()
            .onAppear {
                seedInitialScores()

                if round != nil {
                    Task { await loadExistingScoresIfNeeded() }
                }
            }
            .navigationTitle(round == nil ? "新しい局のスコアを入力" : "第\(round!.roundNumber)局のスコアを編集")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") { focusedField = nil }
                }
            }
            .alert("エラー", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    /// プレイヤーごとの入力行を作る
    private func playerRow(player: Player, pid: String) -> some View {
        let scoreBinding = Binding<Int>(
            get: {
                abs(scores.first(where: { $0.playerID == pid })?.points ?? 0)
            },
            set: { newValue in
                if let idx = scores.firstIndex(where: { $0.playerID == pid }) {
                    let plus = signSelection[pid] ?? true
                    scores[idx].points = plus ? newValue : -newValue
                } else {
                    let plus = signSelection[pid] ?? true
                    let signed = plus ? newValue : -newValue

                    scores.append(
                        Score(
                            id: pid,
                            gameRecordID: recordID,
                            gameResultID: result.id ?? "",
                            gameRoundID: round?.id ?? "",
                            playerID: pid,
                            points: signed,
                            isResting: isResting[pid] ?? false
                        )
                    )
                }
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text(player.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Picker("", selection: Binding(
                    get: { signSelection[pid] ?? true },
                    set: { signSelection[pid] = $0 }
                )) {
                    Text("+").tag(true)
                    Text("-").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 90)

                HStack(spacing: 6) {
                    TextField("スコア", value: scoreBinding, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: pid)
                        .frame(width: 90)

                    Text("00点")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                Button {
                    isResting[pid, default: false].toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isResting[pid, default: false] ? "checkmark.square.fill" : "square")
                            .foregroundColor(.blue)
                            .font(.title3)
                        Text("休み")
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    /// 初期状態のスコア配列を用意する
    private func seedInitialScores() {
        guard scores.isEmpty else { return }

        let rid = round?.id ?? ""

        scores = players.compactMap { p in
            guard let pid = p.id, !pid.isEmpty else { return nil }

            signSelection[pid] = true
            isResting[pid] = false

            return Score(
                id: pid,
                gameRecordID: recordID,
                gameResultID: result.id ?? "",
                gameRoundID: rid,
                playerID: pid,
                points: 0,
                isResting: false
            )
        }
    }

    /// 既存スコアの読み込みを行う
    private func loadExistingScoresIfNeeded() async {
        guard let round, let roundID = round.id else { return }
        guard !isPreview else { return }
        guard !didLoadExistingScores else { return }
        didLoadExistingScores = true

        isLoadingExistingScores = true
        defer { isLoadingExistingScores = false }

        do {
            guard let resultDocID = result.id else { return }

            let ref = Firestore.firestore()
                .collection("gameRecords")
                .document(recordID)
                .collection("gameResults")
                .document(resultDocID)
                .collection("gameRounds")
                .document(roundID)
                .collection("scores")

            let snap = try await ref.getDocuments()

            var fetched: [String: Score] = [:]
            for doc in snap.documents {
                do {
                    let sc = try doc.data(as: Score.self)
                    fetched[sc.playerID] = sc
                } catch {
                    print("❌ decode Score error:", error)
                }
            }

            await MainActor.run {
                for p in players {
                    guard let pid = p.id else { continue }
                    guard let sc = fetched[pid] else { continue }

                    if let idx = scores.firstIndex(where: { $0.playerID == pid }) {
                        scores[idx].points = sc.points
                        scores[idx].isResting = sc.isResting
                    } else {
                        scores.append(sc)
                    }

                    signSelection[pid] = (sc.points >= 0)
                    isResting[pid] = sc.isResting
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "保存済みスコアの読み込みに失敗しました: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    /// スコアを保存する
    private func save() async {
        guard let resultDocID = result.id else { return }

        guard !isPreview else {
            onSaved()
            dismiss()
            return
        }

        do {
            let roundID: String

            if let round, let rid = round.id {
                roundID = rid
            } else {
                let newRef = Firestore.firestore()
                    .collection("gameRecords")
                    .document(recordID)
                    .collection("gameResults")
                    .document(resultDocID)
                    .collection("gameRounds")
                    .document()

                roundID = newRef.documentID

                let newRound = GameRound(
                    id: roundID,
                    gameRecordID: recordID,
                    gameResultID: resultDocID,
                    roundNumber: nextRoundNumber
                )
                try newRef.setData(from: newRound)
            }

            for sc in scores {
                let pid = sc.playerID
                let resting = isResting[pid] ?? false

                let plus = signSelection[pid] ?? true
                let absVal = abs(sc.points)
                let signed = plus ? absVal : -absVal

                let normalized = Score(
                    id: pid,
                    gameRecordID: recordID,
                    gameResultID: resultDocID,
                    gameRoundID: roundID,
                    playerID: pid,
                    points: resting ? 0 : signed,
                    isResting: resting
                )

                try Firestore.firestore()
                    .collection("gameRecords")
                    .document(recordID)
                    .collection("gameResults")
                    .document(resultDocID)
                    .collection("gameRounds")
                    .document(roundID)
                    .collection("scores")
                    .document(pid)
                    .setData(from: normalized, merge: true)
            }

            onSaved()
            dismiss()
        } catch {
            print("❌ save score sheet error:", error)
        }
    }
}

#Preview("新規局（round=nil）") {
    let recordID = "record123"
    let resultID = "session1"

    let result = GameResult(
        id: resultID,
        gameRecordID: recordID,
        date: Date(),
        title: "半荘1回目",
        rate: 50.0,
        basePoints: 25000,
        playerIDs: ["p1", "p2", "p3", "p4"],
        updatedAt: nil
    )

    let players: [Player] = [
        Player(id: "p1", name: "A"),
        Player(id: "p2", name: "B"),
        Player(id: "p3", name: "C"),
        Player(id: "p4", name: "D")
    ]

    return ScoreSheetView(
        recordID: recordID,
        result: result,
        players: players,
        round: nil,
        nextRoundNumber: 1,
        onSaved: {}
    )
}

#Preview("既存局編集（roundあり：初期は0→Firestore注入）") {
    let recordID = "record123"
    let resultID = "session1"

    let result = GameResult(
        id: resultID,
        gameRecordID: recordID,
        date: Date(),
        title: "半荘1回目",
        rate: 50.0,
        basePoints: 25000,
        playerIDs: ["p1", "p2", "p3", "p4"],
        updatedAt: nil
    )

    let players: [Player] = [
        Player(id: "p1", name: "A"),
        Player(id: "p2", name: "B"),
        Player(id: "p3", name: "C"),
        Player(id: "p4", name: "D")
    ]

    let round = GameRound(
        id: "round1",
        gameRecordID: recordID,
        gameResultID: resultID,
        roundNumber: 3
    )

    return ScoreSheetView(
        recordID: recordID,
        result: result,
        players: players,
        round: round,
        nextRoundNumber: 4,
        onSaved: {}
    )
}
