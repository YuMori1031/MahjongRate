//
//  GameSessionListView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// 対局結果の一覧を表示する画面
struct GameSessionListView: View {
    /// 表示対象のゲーム記録
    let record: GameRecord

    /// データ購読を担当する共有ViewModel
    @StateObject private var vm = StorageViewModel.shared

    /// 対局追加シートの表示状態
    @State private var isShowingAddSession: Bool = false

    /// 削除対象として保持する対局
    @State private var pendingDeleteSession: GameResult? = nil
    /// 削除確認ダイアログの表示状態
    @State private var isShowingDeleteConfirm: Bool = false
    /// 対局結果上限アラート表示状態
    @State private var isShowingSessionLimitAlert: Bool = false

    /// 記録に所属する全プレイヤー
    @State private var allPlayers: [Player] = []
    /// プレイヤー一覧の購読
    @State private var playersListener: ListenerRegistration? = nil
    /// 対局ごとの局数
    @State private var roundCounts: [String: Int] = [:]
    /// 対局ごとの局数購読
    @State private var roundCountListeners: [String: ListenerRegistration] = [:]

    /// プレイヤーIDからプレイヤーを引く辞書
    private var playerByID: [String: Player] {
        Dictionary(uniqueKeysWithValues: allPlayers.compactMap { p in
            guard let id = p.id else { return nil }
            return (id, p)
        })
    }

    /// Firestore の読み書きを行う窓口
    private let storage = FirestoreStorage()

    /// ログイン中のユーザーID
    private var myUID: String? { Auth.auth().currentUser?.uid }

    /// 対局の追加や編集が可能かどうか
    private var canManageSessions: Bool {
        guard let uid = myUID else { return false }
        return record.memberIDs.contains(uid) || record.createdBy == uid
    }

    /// 対局結果数の上限に達しているか
    private var hasReachedSessionLimit: Bool {
        vm.gameResults.count >= 100
    }


    /// 対局結果一覧のルートビュー
    var body: some View {
        ZStack {
            sessionList
            floatingAddSessionButton
        }
        .navigationTitle("対局結果一覧")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = record.id {
                vm.startGameResults(for: id)
            }

            startPlayersListenerIfNeeded()
            startRoundCountListenersIfNeeded()
        }
        .onDisappear {
            playersListener?.remove()
            playersListener = nil
            for (_, listener) in roundCountListeners {
                listener.remove()
            }
            roundCountListeners.removeAll()
        }
        .onChange(of: vm.gameResults.map { $0.id ?? "" }) { _, _ in
            startRoundCountListenersIfNeeded()
        }
        .sheet(isPresented: $isShowingAddSession) {
            if let id = record.id {
                NavigationStack {
                    AddGameSessionView(recordID: id)
                }
            } else {
                NavigationStack {
                    Text("recordID が取得できませんでした。")
                        .foregroundColor(.secondary)
                        .navigationTitle("エラー")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .alert(
            "この対局結果を削除しますか？",
            isPresented: $isShowingDeleteConfirm,
            presenting: pendingDeleteSession
        ) { session in
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                Task { await deleteSession(session) }
            }
        } message: { session in
            Text("「\(session.title)」を削除します。")
        }
        .alert("上限に達しました", isPresented: $isShowingSessionLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("対局結果は最大100件まで登録できます。")
        }
    }

    /// 月ごとに並べた対局一覧
    private var sessionList: some View {
        List {
            if groupedSessions.isEmpty {
                Section {
                    Text("まだ対局結果がありません。\n右下の ＋ ボタンから追加してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach(groupedSessions.keys.sorted(by: >), id: \.self) { monthKey in
                    sessionSection(for: monthKey)
                }
            }
        }
    }

    /// 指定月のセクションを生成する
    private func sessionSection(for monthKey: String) -> some View {
        Section(header: Text(monthKey)) {
            ForEach(groupedSessions[monthKey] ?? []) { session in
                sessionRow(session)
            }
        }
    }

    /// 対局の1行表示を作る
    private func sessionRow(_ session: GameResult) -> some View {
        NavigationLink {
            if let recordID = record.id, let resultID = session.id {
                GameResultDetailView(
                    recordID: recordID,
                    resultID: resultID,
                    initialTitle: session.title
                )
            } else {
                Text("ID が取得できませんでした。")
                    .foregroundColor(.secondary)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.body)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .font(.caption2)
                    Text("\(session.date, formatter: DateFormatter.japaneseLongFormat)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    infoPill(
                        icon: "person.2.fill",
                        text: "登録 \(session.playerIDs.count)人"
                    )
                    infoPill(
                        icon: "list.number",
                        text: "対局数 \(roundCountText(for: session))"
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                guard canManageSessions else { return }
                pendingDeleteSession = session
                isShowingDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// 対局のプレイヤー名を連結した文字列
    private func playerNamesText(for session: GameResult) -> String? {
        guard !session.playerIDs.isEmpty else { return nil }
        let names = session.playerIDs.map { playerByID[$0]?.name ?? $0 }
        return names.joined(separator: " / ")
    }

    /// 表示用の局数
    private func roundCountText(for session: GameResult) -> String {
        guard let id = session.id else { return "0" }
        return "\(roundCounts[id, default: 0])"
    }

    /// 情報表示用のピル
    private func infoPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    /// 対局追加ボタンのフローティング表示
    private var floatingAddSessionButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    if hasReachedSessionLimit {
                        isShowingSessionLimitAlert = true
                    } else {
                        isShowingAddSession = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                        .accessibilityLabel("対局結果を追加")
                }
                .padding(24)
            }
        }
    }

    /// 月ごとの文字列でグルーピングした対局一覧
    private var groupedSessions: [String: [GameResult]] {
        Dictionary(grouping: vm.gameResults) { session in
            Self.monthFormatter.string(from: session.date)
        }
    }

    /// 月表示用のフォーマッタ
    private static let monthFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy年MM月"
        df.locale = Locale(identifier: "ja_JP")
        return df
    }()

    /// プレイヤー一覧の購読を開始する
    private func startPlayersListenerIfNeeded() {
        guard playersListener == nil else { return }
        guard let recordID = record.id, !recordID.isEmpty else { return }

        playersListener = storage.subscribePlayers(for: recordID) { list in
            Task { @MainActor in
                self.allPlayers = list
            }
        }
    }

    /// 対局ごとの局数購読を開始する
    private func startRoundCountListenersIfNeeded() {
        guard let recordID = record.id, !recordID.isEmpty else { return }

        let sessionIDs = Set(vm.gameResults.compactMap { $0.id })

        for id in sessionIDs {
            if roundCountListeners[id] != nil { continue }
            roundCountListeners[id] = storage.subscribeGameRounds(
                for: recordID,
                resultID: id
            ) { list in
                Task { @MainActor in
                    roundCounts[id] = list.count
                }
            }
        }

        for (id, listener) in roundCountListeners where !sessionIDs.contains(id) {
            listener.remove()
            roundCountListeners.removeValue(forKey: id)
            roundCounts.removeValue(forKey: id)
        }
    }


    /// 対局情報を削除する
    @MainActor
    private func deleteSession(_ session: GameResult) async {
        guard canManageSessions else { return }
        guard let recordID = record.id else { return }
        guard let sessionID = session.id else { return }

        do {
            try await FirestoreStorage().deleteGameResult(recordID: recordID, resultID: sessionID)
        } catch {
            print("❌ deleteSession error:", error)
        }
    }
}

#Preview {
    GameSessionListPreview()
}

/// 対局結果一覧のプレビュー
private struct GameSessionListPreview: View {
    init() {
        let vm = StorageViewModel.shared
        vm.gameResults = [
            GameResult(
                id: "session1",
                gameRecordID: "record123",
                date: Date(),
                title: "半荘1回目",
                rate: 50.0,
                basePoints: 25000,
                playerIDs: ["p1", "p2", "p3", "p4"],
                updatedAt: nil
            ),
            GameResult(
                id: "session2",
                gameRecordID: "record123",
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                title: "半荘2回目",
                rate: 20.0,
                basePoints: 30000,
                playerIDs: ["p1", "p2", "p5"],
                updatedAt: nil
            )
        ]
    }

    var body: some View {
        NavigationStack {
            GameSessionListView(
                record: GameRecord(
                    id: "record123",
                    date: Date(),
                    title: "自宅麻雀",
                    description: "半荘赤ドラあり",
                    createdBy: "user123",
                    memberIDs: ["user123", "user456", "user789"],
                    inviteCode: "ABCD2345",
                    updatedAt: nil
                )
            )
        }
    }
}
