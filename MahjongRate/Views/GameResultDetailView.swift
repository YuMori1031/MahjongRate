//
//  GameResultDetailView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseFirestore

/// 対局結果の詳細を表示する画面
struct GameResultDetailView: View {
    /// 対象のゲーム記録ID
    let recordID: String
    /// 対象の対局ID
    let resultID: String
    /// 初期表示用の対局タイトル
    let initialTitle: String

    /// Firestore の読み書きを行う窓口
    private let storage = FirestoreStorage()

    /// 取得済みの対局情報
    @State private var liveResult: GameResult? = nil
    /// 記録に所属する全プレイヤー
    @State private var allPlayers: [Player] = []
    /// 対局内の局一覧
    @State private var rounds: [GameRound] = []
    /// 局IDごとのスコア一覧
    @State private var scoresByRoundID: [String: [Score]] = [:]

    /// 対局情報の購読
    @State private var resultListener: ListenerRegistration? = nil
    /// プレイヤー一覧の購読
    @State private var playersListener: ListenerRegistration? = nil
    /// 局一覧の購読
    @State private var roundsListener: ListenerRegistration? = nil
    /// 局ごとのスコア購読
    @State private var scoresListeners: [String: ListenerRegistration] = [:]

    /// スコアシート遷移の種類
    private enum ScoreSheetRoute: Identifiable {
        case new
        case edit(GameRound)

        var id: String {
            switch self {
            case .new:
                return "new"
            case .edit(let r):
                return "edit-\(r.id ?? UUID().uuidString)"
            }
        }
    }

    /// スコアシートの表示先
    @State private var scoreSheetRoute: ScoreSheetRoute? = nil
    /// 編集シートの表示状態
    @State private var isShowingEditSheet = false
    /// 局数上限アラートの表示状態
    @State private var isShowingRoundLimitAlert = false

    /// プレイヤー名ダイアログの表示状態
    @State private var showingPlayerNameDialog = false
    /// ダイアログに表示する名前
    @State private var dialogPlayerName: String = ""

    /// レート候補の一覧
    private let rateOptions: [Double] = [10.0, 20.0, 50.0, 100.0]
    /// 原点候補の一覧
    private let basePointsOptions: [Int] = [25000, 30000, 35000]

    /// プレビュー実行中かどうか
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// 画面タイトルに使う対局名
    private var navigationTitleText: String {
        liveResult?.title ?? initialTitle
    }

    /// 参加プレイヤーの並び
    private var players: [Player] {
        guard let liveResult else { return [] }

        var dict: [String: Player] = [:]
        for p in allPlayers {
            guard let id = p.id else { continue }
            dict[id] = p
        }

        return liveResult.playerIDs.compactMap { dict[$0] }
    }

    /// 表示用に整形した局一覧
    private var roundsForDisplay: [RoundDisplay] {
        rounds
            .sorted { $0.roundNumber < $1.roundNumber }
            .map { r in
                let list = scoresByRoundID[r.id ?? ""] ?? []
                return RoundDisplay(round: r, scores: list)
            }
    }

    /// 局数の上限に達しているか
    private var hasReachedRoundLimit: Bool {
        rounds.count >= 20
    }

    /// プレイヤー別の合計点
    private var totalScores: [String: Int] {
        var totals: [String: Int] = [:]
        for p in players {
            guard let pid = p.id else { continue }
            let total = roundsForDisplay.reduce(0) { sum, rd in
                sum + (rd.scores.first { $0.playerID == pid }?.points ?? 0)
            }
            totals[pid] = total
        }
        return totals
    }

    /// 収支の最終スコア
    private var finalScores: [String: Double] {
        guard let liveResult else { return [:] }

        var results: [String: Double] = [:]

        for p in players {
            guard let pid = p.id else { continue }

            let playedScores: [Score] = roundsForDisplay.compactMap { rd in
                guard let sc = rd.scores.first(where: { $0.playerID == pid }) else { return nil }
                return sc.isResting ? nil : sc
            }

            let playedCount = playedScores.count
            guard playedCount > 0 else {
                results[pid] = 0.0
                continue
            }

            let totalActualPoints = playedScores.reduce(0) { sum, sc in
                sum + (sc.points * 100)
            }

            let roundedTotal = roundToNearestThousand(totalActualPoints)
            let baseTotal = liveResult.basePoints * playedCount
            let diff = roundedTotal - baseTotal
            let rateFactor = liveResult.rate / 1000.0
            results[pid] = Double(diff) * rateFactor
        }

        return results
    }

    /// 対局結果の詳細ビュー
    var body: some View {
        VStack {
            if liveResult == nil {
                ProgressView("読み込み中…")
                    .padding()
            } else {
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .padding(.bottom, 0)
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("編集") {
                    isShowingEditSheet = true
                }
                .disabled(liveResult == nil)
            }
        }
        .task {
            if isPreview {
                #if DEBUG
                self.allPlayers = PreviewData.players
                self.liveResult = PreviewData.gameResults.first { $0.id == resultID }
                self.rounds = PreviewData.rounds
                self.scoresByRoundID = PreviewData.scoresByRoundID
                #endif
            } else {
                startListening()
            }
        }
        .onDisappear { stopListening() }
        .sheet(isPresented: $isShowingEditSheet) {
            if let liveResult {
                NavigationStack {
                    EditGameResultView(
                        recordID: recordID,
                        resultID: resultID,
                        initial: liveResult,
                        rateOptions: rateOptions,
                        basePointsOptions: basePointsOptions
                    )
                }
            } else {
                NavigationStack {
                    Text("読み込み中のため編集できません。")
                        .foregroundColor(.secondary)
                        .navigationTitle("編集")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .sheet(item: $scoreSheetRoute) { route in
            if let liveResult {
                NavigationStack {
                    if players.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("プレイヤーを読み込み中…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else {
                        switch route {
                        case .new:
                            ScoreSheetView(
                                recordID: recordID,
                                result: liveResult,
                                players: players,
                                round: nil,
                                nextRoundNumber: (rounds.map { $0.roundNumber }.max() ?? 0) + 1
                            ) { }
                        case .edit(let r):
                            ScoreSheetView(
                                recordID: recordID,
                                result: liveResult,
                                players: players,
                                round: r,
                                nextRoundNumber: (rounds.map { $0.roundNumber }.max() ?? 0) + 1
                            ) { }
                        }
                    }
                }
            }
        }
        .alert("上限に達しました", isPresented: $isShowingRoundLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("この対局の局は最大20局まで登録できます。")
        }
        .overlay {
            if showingPlayerNameDialog {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingPlayerNameDialog = false
                        }

                    VStack(spacing: 10) {
                        Text("プレイヤー名")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(dialogPlayerName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: 280)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                    .shadow(radius: 10, y: 4)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: showingPlayerNameDialog)
            }
        }
    }

    /// 詳細表示の主要コンテンツ
    private var mainContent: some View {
        let result = liveResult!

        return VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("対局情報")
                    .font(.caption)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                            .frame(width: 18)

                        Text("対局日")

                        Spacer()

                        Text("\(result.date, formatter: DateFormatter.japaneseLongFormat)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 10) {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(.green)
                        Text("レート")
                        Spacer()
                        Text("\(Int(result.rate))ポイント")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .foregroundColor(.orange)
                        Text("原点")
                        Spacer()
                        Text("\(result.basePoints)点")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)

                }
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .shadow(radius: 2, y: 1)
            }
            .padding(.horizontal, 4)

            if roundsForDisplay.isEmpty {
                Text("対局記録がありません")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        summaryCard

                        ForEach(roundsForDisplay) { rd in
                            roundCard(for: rd)
                        }
                    }
                    .padding(.bottom)
                }
            }

            Spacer(minLength: 0)

            Button {
                if hasReachedRoundLimit {
                    isShowingRoundLimitAlert = true
                } else {
                    scoreSheetRoute = .new
                }
            } label: {
                Text("記録追加")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .disabled(players.isEmpty || hasReachedRoundLimit)
            .foregroundColor(.white)
            .background((players.isEmpty || hasReachedRoundLimit) ? Color.gray.opacity(0.35) : Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 1)
            .padding(.bottom, 12)
        }
    }

    /// 局ごとのカード表示
    private func roundCard(for rd: RoundDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    scoreSheetRoute = .edit(rd.round)
                } label: {
                    Text("第\(rd.round.roundNumber)局")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await deleteRound(rd.round) }
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }

                Spacer()
            }

            ForEach(Array(players.enumerated()), id: \.offset) { index, player in
                let pid = player.id ?? ""
                let sc = rd.scores.first { $0.playerID == pid }
                let isResting = sc?.isResting == true
                let points = sc?.points ?? 0

                HStack {
                    Button {
                        dialogPlayerName = player.name
                        showingPlayerNameDialog = true
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text(String(player.name.prefix(1)))
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                )
                            Text(player.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isResting {
                        Text("休")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Text("\(points)")
                            .font(.subheadline)
                            .foregroundColor(scoreColor(points: points, isResting: false))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(scoreColor(points: points, isResting: false).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())

                if index < players.count - 1 {
                    Divider()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(radius: 2, y: 1)
        .padding(.horizontal, 4)
    }

    /// 最終成績のカード表示
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.orange)
                Text("最終成績")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.blue.opacity(0.6), lineWidth: 1)
            )

            ForEach(Array(players.enumerated()), id: \.offset) { index, player in
                let pid = player.id ?? ""
                let total = totalScores[pid] ?? 0
                let final = Int(finalScores[pid] ?? 0.0)

                HStack {
                    Button {
                        dialogPlayerName = player.name
                        showingPlayerNameDialog = true
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.orange.opacity(0.18))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text(String(player.name.prefix(1)))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                )
                            Text(player.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("合計 \(total)")
                            .font(.caption)
                            .foregroundColor(scoreColor(points: total, isResting: false))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(scoreColor(points: total, isResting: false).opacity(0.12))
                            .clipShape(Capsule())
                        Text("収支 \(final)")
                            .font(.subheadline)
                            .foregroundColor(scoreColor(points: final, isResting: false))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(scoreColor(points: final, isResting: false).opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 6)

                if index < players.count - 1 {
                    Divider()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .shadow(radius: 2, y: 1)
        .padding(.horizontal, 4)
    }

    /// 点数に応じた表示色を返す
    private func scoreColor(points: Int, isResting: Bool) -> Color {
        if isResting { return .secondary }
        if points > 0 { return .blue }
        if points < 0 { return .red }
        return .primary
    }

    /// 点数を1000点単位に丸める
    private func roundToNearestThousand(_ score: Int) -> Int {
        let remainder = score % 1000
        if remainder >= 500 { return score + (1000 - remainder) }
        return score - remainder
    }

    /// Firestore の購読を開始する
    private func startListening() {
        startResultListener()
        startPlayersListener()
        startRoundsListener()
    }

    /// Firestore の購読を停止する
    private func stopListening() {
        resultListener?.remove(); resultListener = nil
        playersListener?.remove(); playersListener = nil
        roundsListener?.remove(); roundsListener = nil

        for (_, l) in scoresListeners { l.remove() }
        scoresListeners.removeAll()
    }

    /// 対局情報の購読を開始する
    private func startResultListener() {
        guard resultListener == nil else { return }

        let ref = Firestore.firestore()
            .collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)

        resultListener = ref.addSnapshotListener { snap, error in
            if let error { print("❌ result listener error:", error); return }
            guard let snap, snap.exists else { return }

            do {
                let decoded = try snap.data(as: GameResult.self)
                Task { @MainActor in self.liveResult = decoded }
            } catch {
                print("❌ decode GameResult error:", error)
            }
        }
    }

    /// プレイヤー一覧の購読を開始する
    private func startPlayersListener() {
        guard playersListener == nil else { return }

        playersListener = storage.subscribePlayers(for: recordID) { list in
            Task { @MainActor in self.allPlayers = list }
        }
    }

    /// 局一覧の購読を開始する
    private func startRoundsListener() {
        guard roundsListener == nil else { return }

        roundsListener = storage.subscribeGameRounds(
            for: recordID,
            resultID: resultID
        ) { list in
            Task { @MainActor in
                self.rounds = list
                self.reconcileScoresListeners(with: list)
            }
        }
    }

    /// 局一覧に合わせてスコア購読を調整する
    @MainActor
    private func reconcileScoresListeners(with newRounds: [GameRound]) {
        let newIDs: Set<String> = Set(newRounds.compactMap { $0.id })
        let currentIDs: Set<String> = Set(scoresListeners.keys)

        let removed = currentIDs.subtracting(newIDs)
        for id in removed {
            scoresListeners[id]?.remove()
            scoresListeners[id] = nil
            scoresByRoundID[id] = nil
        }

        let added = newIDs.subtracting(currentIDs)
        for rid in added {
            let l = storage.subscribeScores(
                for: recordID,
                resultID: resultID,
                roundID: rid
            ) { scores in
                Task { @MainActor in self.scoresByRoundID[rid] = scores }
            }
            scoresListeners[rid] = l
        }
    }

    /// 局を削除し番号を詰める
    @MainActor
    private func deleteRound(_ round: GameRound) async {
        guard let rid = round.id else { return }

        do {
            try await storage.deleteGameRound(id: rid, recordID: recordID, resultID: resultID)

            var latest = try await storage.fetchGameRounds(for: recordID, resultID: resultID)
            latest.sort { $0.roundNumber < $1.roundNumber }

            for (idx, r) in latest.enumerated() {
                guard let id = r.id else { continue }
                let newNo = idx + 1
                if r.roundNumber != newNo {
                    try await Firestore.firestore()
                        .collection("gameRecords")
                        .document(recordID)
                        .collection("gameResults")
                        .document(resultID)
                        .collection("gameRounds")
                        .document(id)
                        .updateData(["roundNumber": newNo])
                }
            }
        } catch {
            print("❌ deleteRound error:", error)
        }
    }
}

/// 表示用に局とスコアをまとめたモデル
private struct RoundDisplay: Identifiable {
    /// 表示用の識別子
    var id: String { round.id ?? UUID().uuidString }
    /// 対局の局
    let round: GameRound
    /// 局のスコア一覧
    let scores: [Score]
}

#Preview {
    NavigationStack {
        GameResultDetailView(recordID: "record123", resultID: "session1", initialTitle: "テスト対局")
    }
}
