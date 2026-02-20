//
//  StorageViewModel.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Firestoreのデータ購読と操作をまとめるViewModel
@MainActor
final class StorageViewModel: ObservableObject {
    /// 共有インスタンス
    static let shared = StorageViewModel()

    /// Firestoreアクセス層
    private let service = FirestoreStorage()
    private var listeners: [ListenerRegistration] = []
    private var myGameRecordsListener: ListenerRegistration? = nil
    private var membersListener: ListenerRegistration? = nil

    /// メンバー一覧
    @Published var members: [Member] = []
    /// 対局記録一覧
    @Published var gameRecords: [GameRecord] = []
    /// 対局結果一覧
    @Published var gameResults: [GameResult] = []
    /// ラウンド一覧
    @Published var gameRounds: [GameRound] = []
    /// スコア一覧
    @Published var scores: [Score] = []
    /// 対局記録の読み込み中フラグ
    @Published var isLoadingMyGameRecords: Bool = false

    /// 月別にグルーピングした対局記録
    var groupedRecords: [String: [GameRecord]] {
        Dictionary(grouping: gameRecords) { record in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年MM月"
            let baseDate = record.updatedAt?.dateValue() ?? record.date
            return formatter.string(from: baseDate)
        }
    }

    private init() {}

    deinit {
        listeners.forEach { $0.remove() }
        myGameRecordsListener?.remove()
    }

    /// 監視と保持データを初期化する
    func reset() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()

        myGameRecordsListener?.remove()
        myGameRecordsListener = nil

        members = []
        gameRecords = []
        gameResults = []
        gameRounds = []
        scores = []
    }

    /// メンバーの購読を開始する
    func startMembers() {
        if membersListener != nil { return }

        Task {
            do { members = try await service.fetchMembers() }
            catch { print("❌ fetchMembers error:", error) }
        }

        let sub = service.subscribeMembers { [weak self] updated in
            Task { @MainActor in self?.members = updated }
        }
        membersListener = sub
        listeners.append(sub)
    }

    /// メンバーを追加する
    func addMember(name: String) {
        let m = Member(
            id: nil,
            name: name,
            email: nil,
            iconURL: nil
        )
        Task {
            do {
                try await service.addMember(m)
            } catch {
                print("❌ addMember error:", error)
            }
        }
    }

    /// メンバーを削除する
    func deleteMember(id: String) {
        Task {
            do {
                try await service.deleteMember(id: id)
            } catch {
                print("❌ deleteMember error:", error)
            }
        }
    }

    /// 自分の対局記録の購読を開始する
    func startMyGameRecords() {
        myGameRecordsListener?.remove()
        myGameRecordsListener = nil

        isLoadingMyGameRecords = true

        var didFinishInitialLoad = false
        let sub = service.subscribeGameRecords { [weak self] updated in
            Task { @MainActor in
                guard let self else { return }
                self.gameRecords = updated

                if !didFinishInitialLoad {
                    didFinishInitialLoad = true
                    self.isLoadingMyGameRecords = false
                }
            }
        }

        myGameRecordsListener = sub
        listeners.append(sub)
    }

    /// 自分の対局記録の購読を停止する
    func stopMyGameRecords() {
        myGameRecordsListener?.remove()
        myGameRecordsListener = nil

        gameRecords = []
    }

    /// 対局記録を追加する
    func addGameRecord(date: Date,
                       title: String,
                       description: String? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ addGameRecord error: 未ログイン")
            return
        }
        Task {
            do {
                let inviteCode = try await service.generateUniqueInviteCode()
                let record = GameRecord(
                    id: nil,
                    date: date,
                    title: title,
                    description: description,
                    createdBy: uid,
                    memberIDs: [uid],
                    inviteCode: inviteCode,
                    updatedAt: nil
                )
                try await service.addGameRecord(record)
            } catch {
                print("❌ addGameRecord error:", error)
            }
        }
    }

    /// 対局記録を退会または削除する
    func leaveOrDeleteGameRecord(_ record: GameRecord) {
        Task {
            do {
                try await leaveOrDeleteGameRecordAsync(record)
            } catch {
                print("❌ leaveOrDeleteGameRecord error:", error)
            }
        }
    }

    /// 対局記録を退会または削除する
    private func leaveOrDeleteGameRecordAsync(_ record: GameRecord) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ leaveOrDeleteGameRecord: 未ログイン")
            return
        }
        guard let recordID = record.id else {
            print("❌ leaveOrDeleteGameRecord: record に id がありません")
            return
        }

        let members = record.memberIDs
        let remaining = members.filter { $0 != uid }

        if remaining.isEmpty {
            try await service.deleteGameRecord(id: recordID)
            return
        }

        var update: [String: Any] = [
            "memberIDs": remaining
        ]

        if record.createdBy == uid, let newOwner = remaining.first {
            update["createdBy"] = newOwner
        }

        let db = Firestore.firestore()
        try await db.collection("gameRecords")
            .document(recordID)
            .updateData(update)
    }

    /// 招待コードで対局記録に参加する
    func joinGameRecord(byInviteCode code: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ joinGameRecord error: 未ログイン")
            return
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let db = Firestore.firestore()

        let snapshot = try await db.collection("gameRecords")
            .whereField("inviteCode", isEqualTo: trimmed)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else {
            throw JoinError.notFound
        }

        let ref = doc.reference
        let pendingRef = ref.collection("pendingMembers").document(uid)

        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let current = try transaction.getDocument(ref)
                let memberIDs = current.data()?["memberIDs"] as? [String] ?? []

                if memberIDs.contains(uid) {
                    return nil
                }

                let pendingSnap = try? transaction.getDocument(pendingRef)
                if pendingSnap?.exists == true {
                    return nil
                }

                transaction.setData(
                    [
                        "memberID": uid,
                        "requestedAt": FieldValue.serverTimestamp()
                    ],
                    forDocument: pendingRef,
                    merge: true
                )
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            return nil
        }
    }

    /// 参加エラー種別
    enum JoinError: Error {
        case notFound
    }

    /// 対局結果の購読を開始する
    func startGameResults(for recordID: String) {
        Task {
            do {
                gameResults = try await service.fetchGameResults(for: recordID)
            } catch {
                print("❌ fetchGameResults error:", error)
            }
        }
        let sub = service.subscribeGameResults(for: recordID) { [weak self] updated in
            Task { @MainActor in
                self?.gameResults = updated
            }
        }
        listeners.append(sub)
    }

    /// 対局結果を追加する
    func addGameResult(
        date: Date,
        title: String,
        rate: Double,
        basePoints: Int,
        recordID: String,
        players: [Player]
    ) {
        let ids = players.compactMap { $0.id }

        let result = GameResult(
            id: nil,
            gameRecordID: recordID,
            date: date,
            title: title,
            rate: rate,
            basePoints: basePoints,
            playerIDs: ids,
            updatedAt: nil
        )

        Task {
            do {
                try await service.addGameResult(result, to: recordID)
            } catch {
                print("❌ addGameResult error:", error)
            }
        }
    }

    /// 対局結果を削除する
    func deleteGameResult(resultID: String, recordID: String) {
        Task {
            do {
                try await service.deleteGameResult(recordID: recordID, resultID: resultID)
            } catch {
                print("❌ deleteGameResult error:", error)
            }
        }
    }

    /// ラウンドの購読を開始する
    func startGameRounds(recordID: String, resultID: String) {
        Task {
            do {
                gameRounds = try await service.fetchGameRounds(for: recordID, resultID: resultID)
            } catch {
                print("❌ fetchGameRounds error:", error)
            }
        }
        let sub = service.subscribeGameRounds(for: recordID, resultID: resultID) { [weak self] updated in
            Task { @MainActor in
                self?.gameRounds = updated
            }
        }
        listeners.append(sub)
    }

    /// ラウンドを追加する
    func addGameRound(roundNumber: Int,
                      recordID: String,
                      resultID: String) {
        let round = GameRound(
            id: nil,
            gameRecordID: recordID,
            gameResultID: resultID,
            roundNumber: roundNumber
        )
        Task {
            do {
                try await service.addGameRound(round)
            } catch {
                print("❌ addGameRound error:", error)
            }
        }
    }

    /// ラウンドを削除する
    func deleteGameRound(id: String,
                         recordID: String,
                         resultID: String) {
        Task {
            do {
                try await service.deleteGameRound(
                    id: id,
                    recordID: recordID,
                    resultID: resultID
                )
            } catch {
                print("❌ deleteGameRound error:", error)
            }
        }
    }

    /// スコアの購読を開始する
    func startScores(recordID: String,
                     resultID: String,
                     roundID: String) {
        Task {
            do {
                scores = try await service.fetchScores(
                    for: recordID,
                    resultID: resultID,
                    roundID: roundID
                )
            } catch {
                print("❌ fetchScores error:", error)
            }
        }
        let sub = service.subscribeScores(
            for: recordID,
            resultID: resultID,
            roundID: roundID
        ) { [weak self] updated in
            Task { @MainActor in
                self?.scores = updated
            }
        }
        listeners.append(sub)
    }

    /// スコアを追加する
    func addScore(playerID: String,
                  points: Int,
                  isResting: Bool,
                  recordID: String,
                  resultID: String,
                  roundID: String) {
        let score = Score(
            id: nil,
            gameRecordID: recordID,
            gameResultID: resultID,
            gameRoundID: roundID,
            playerID: playerID,
            points: points,
            isResting: isResting,
            updatedAt: nil
        )
        Task {
            do {
                try await service.addScore(score)
            } catch {
                print("❌ addScore error:", error)
            }
        }
    }

    /// スコアを削除する
    func deleteScore(id: String,
                     recordID: String,
                     resultID: String,
                     roundID: String) {
        Task {
            do {
                try await service.deleteScore(
                    id: id,
                    recordID: recordID,
                    resultID: resultID,
                    roundID: roundID
                )
            } catch {
                print("❌ deleteScore error:", error)
            }
        }
    }
}
