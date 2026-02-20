//
//  FirestoreStorage.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Firestoreアクセスを集約するストレージ層
final class FirestoreStorage {

    /// Firestoreインスタンス
    private let db = Firestore.firestore()

    /// 招待コード生成に使用する文字列
    private let inviteCodeChars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    /// リスナー不要時に使うダミー実装
    final class NoopListenerRegistration: NSObject, ListenerRegistration {
        /// 解除処理を行わない
        func remove() { /* noop */ }
    }

    /// 現在のユーザーのメンバー情報を必要に応じて作成する
    func ensureCurrentUserMemberExists() async throws {
        guard let user = Auth.auth().currentUser else {
            print("❌ ensureCurrentUserMemberExists: 未ログイン")
            return
        }

        let uid = user.uid
        let ref = db.collection("members").document(uid)

        let snap = try await ref.getDocument()
        if snap.exists { return }

        let fallbackName: String = {
            if let name = user.displayName, !name.isEmpty { return name }
            if let email = user.email, let head = email.split(separator: "@").first {
                return String(head)
            }
            return "ユーザー"
        }()

        let member = Member(
            id: uid,
            name: fallbackName,
            email: user.email,
            iconURL: user.photoURL?.absoluteString,
            iconPath: nil
        )

        try ref.setData(from: member, merge: true)
        print("✅ members/\(uid) を新規作成しました")
    }

    /// メンバー情報を保存する
    func addMember(_ member: Member) async throws {
        guard let user = Auth.auth().currentUser else {
            print("❌ addMember error: 未ログイン")
            return
        }

        let uid = user.uid

        var data = member
        data.id = uid
        if data.email == nil {
            data.email = user.email
        }

        try db.collection("members")
            .document(uid)
            .setData(from: data, merge: true)
    }

    /// 自分のアイコン情報を更新する
    func updateMyMemberIcon(iconURL: String?, iconPath: String?) async throws {
        guard let user = Auth.auth().currentUser else {
            print("❌ updateMyMemberIcon error: 未ログイン")
            return
        }

        let ref = db.collection("members").document(user.uid)

        var data: [String: Any] = [:]

        if let iconURL, !iconURL.isEmpty {
            data["iconURL"] = iconURL
        } else {
            data["iconURL"] = FieldValue.delete()
        }

        if let iconPath, !iconPath.isEmpty {
            data["iconPath"] = iconPath
        } else {
            data["iconPath"] = FieldValue.delete()
        }

        try await ref.setData(data, merge: true)
    }

    /// 全メンバー一覧を取得する
    func fetchMembers() async throws -> [Member] {
        let snap = try await db.collection("members").getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Member.self) }
    }

    /// メンバー一覧の更新を購読する
    @discardableResult
    func subscribeMembers(
        onUpdate: @escaping ([Member]) -> Void
    ) -> ListenerRegistration {
        return db.collection("members")
            .addSnapshotListener { snap, error in
                if let error = error {
                    print("Firestore subscribeMembers エラー:", error)
                    return
                }
                let list = snap?.documents.compactMap {
                    try? $0.data(as: Member.self)
                } ?? []
                onUpdate(list)
            }
    }

    /// メンバーを削除する
    func deleteMember(id: String) async throws {
        try await db.collection("members").document(id).delete()
    }

    /// 対局記録を追加する
    func addGameRecord(_ record: GameRecord) async throws {
        let ref = record.id
            .flatMap { db.collection("gameRecords").document($0) }
            ?? db.collection("gameRecords").document()
        try ref.setData(from: record)
    }

    /// 既存と重複しない招待コードを生成する
    func generateUniqueInviteCode(
        length: Int = 8,
        maxAttempts: Int = 10
    ) async throws -> String {
        for _ in 0..<maxAttempts {
            let code = String((0..<length).compactMap { _ in inviteCodeChars.randomElement() })
            let snap = try await db.collection("gameRecords")
                .whereField("inviteCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()
            if snap.documents.isEmpty {
                return code
            }
        }
        throw NSError(domain: "InviteCode", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "招待コードの生成に失敗しました。"
        ])
    }

    /// 参加中の対局記録を取得する
    func fetchGameRecords() async throws -> [GameRecord] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snap = try await db.collection("gameRecords")
            .whereField("memberIDs", arrayContains: uid)
            .getDocuments()

        var list = snap.documents.compactMap { try? $0.data(as: GameRecord.self) }

        list.sort { lhs, rhs in
            let lDate = lhs.updatedAt?.dateValue() ?? lhs.date
            let rDate = rhs.updatedAt?.dateValue() ?? rhs.date
            return lDate > rDate
        }

        return list
    }

    /// 対局記録の更新を購読する
    @discardableResult
    func subscribeGameRecords(
        onUpdate: @escaping ([GameRecord]) -> Void
    ) -> ListenerRegistration {

        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            onUpdate([])
            return NoopListenerRegistration()
        }

        return db.collection("gameRecords")
            .whereField("memberIDs", arrayContains: uid)
            .addSnapshotListener { snap, error in
                if let error = error as NSError? {
                    if error.domain == FirestoreErrorDomain,
                       error.code == FirestoreErrorCode.permissionDenied.rawValue,
                       Auth.auth().currentUser == nil {
                        return
                    }
                    print("Firestore subscribeGameRecords エラー:", error)
                    return
                }

                var list = snap?.documents.compactMap {
                    try? $0.data(as: GameRecord.self)
                } ?? []

                list.sort { lhs, rhs in
                    let lDate = lhs.updatedAt?.dateValue() ?? lhs.date
                    let rDate = rhs.updatedAt?.dateValue() ?? rhs.date
                    return lDate > rDate
                }

                onUpdate(list)
            }
    }

    /// 対局記録と関連データを削除する
    func deleteGameRecord(id: String) async throws {
        let recordRef = db.collection("gameRecords").document(id)

        let playersSnap = try await recordRef.collection("players").getDocuments()
        for playerDoc in playersSnap.documents {
            try await playerDoc.reference.delete()
        }

        let resultsSnap = try await recordRef.collection("gameResults").getDocuments()
        for resultDoc in resultsSnap.documents {
            let roundsSnap = try await resultDoc.reference.collection("gameRounds").getDocuments()
            for roundDoc in roundsSnap.documents {
                let scoresSnap = try await roundDoc.reference.collection("scores").getDocuments()
                for scoreDoc in scoresSnap.documents {
                    try await scoreDoc.reference.delete()
                }
                try await roundDoc.reference.delete()
            }
            try await resultDoc.reference.delete()
        }

        try await recordRef.delete()
    }

    /// 対局記録の更新日時を更新する
    func gameRecordUpdatedAt(recordID: String) async throws {
        try await db.collection("gameRecords")
            .document(recordID)
            .updateData([
                "updatedAt": FieldValue.serverTimestamp()
            ])
    }

    /// 対局結果を追加する
    func addGameResult(_ result: GameResult, to recordID: String) async throws {
        let col = db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
        let ref = result.id.flatMap { col.document($0) } ?? col.document()
        try ref.setData(from: result)
        try await gameRecordUpdatedAt(recordID: recordID)
    }

    /// 対局結果を取得する
    func fetchGameResults(for recordID: String) async throws -> [GameResult] {
        let snap = try await db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .order(by: "date", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: GameResult.self) }
    }

    /// 対局結果の更新を購読する
    @discardableResult
    func subscribeGameResults(
        for recordID: String,
        onUpdate: @escaping ([GameResult]) -> Void
    ) -> ListenerRegistration {

        guard !recordID.isEmpty else {
            onUpdate([])
            return NoopListenerRegistration()
        }

        return db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .order(by: "date", descending: true)
            .addSnapshotListener { snap, error in
                if let error = error {
                    print("Firestore subscribeGameResults エラー:", error)
                    return
                }
                let list = snap?.documents.compactMap {
                    try? $0.data(as: GameResult.self)
                } ?? []
                onUpdate(list)
            }
    }

    /// 対局結果と関連データを削除する
    func deleteGameResult(recordID: String, resultID: String) async throws {
        let resultRef = db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)

        let roundsSnap = try await resultRef.collection("gameRounds").getDocuments()
        for roundDoc in roundsSnap.documents {
            let scoresSnap = try await roundDoc.reference.collection("scores").getDocuments()
            for scoreDoc in scoresSnap.documents {
                try await scoreDoc.reference.delete()
            }
            try await roundDoc.reference.delete()
        }
        try await resultRef.delete()

        try await gameRecordUpdatedAt(recordID: recordID)
    }

    /// プレイヤー一覧の更新を購読する
    @discardableResult
    func subscribePlayers(
        for recordID: String,
        onUpdate: @escaping ([Player]) -> Void
    ) -> ListenerRegistration {

        guard !recordID.isEmpty else {
            onUpdate([])
            return NoopListenerRegistration()
        }

        return db.collection("gameRecords")
            .document(recordID)
            .collection("players")
            .order(by: "name")
            .addSnapshotListener { snap, error in
                if let error {
                    print("❌ subscribePlayers(for:) error:", error)
                    return
                }
                let list = snap?.documents.compactMap { try? $0.data(as: Player.self) } ?? []
                onUpdate(list)
            }
    }

    /// プレイヤーを追加する
    func addPlayer(
        to recordID: String,
        name: String
    ) async throws -> Player {

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordID.isEmpty, !trimmed.isEmpty else {
            throw URLError(.badURL)
        }

        let ref = db.collection("gameRecords")
            .document(recordID)
            .collection("players")
            .document()

        let player = Player(id: ref.documentID, name: trimmed)
        try ref.setData(from: player)
        return player
    }

    /// プレイヤー名を更新する
    func updatePlayer(
        in recordID: String,
        playerID: String,
        name: String
    ) async throws {

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordID.isEmpty, !playerID.isEmpty, !trimmed.isEmpty else { return }

        try await db.collection("gameRecords")
            .document(recordID)
            .collection("players")
            .document(playerID)
            .updateData(["name": trimmed])
    }

    /// プレイヤーを削除する
    func deletePlayer(
        in recordID: String,
        playerID: String
    ) async throws {

        guard !recordID.isEmpty, !playerID.isEmpty else { return }

        try await db.collection("gameRecords")
            .document(recordID)
            .collection("players")
            .document(playerID)
            .delete()
    }

    /// 指定プレイヤーのスコアが存在するかどうか
    func hasScores(
        for recordID: String,
        playerID: String
    ) async throws -> Bool {
        guard !recordID.isEmpty, !playerID.isEmpty else { return false }

        let snap = try await db
            .collectionGroup("scores")
            .whereField("gameRecordID", isEqualTo: recordID)
            .whereField("playerID", isEqualTo: playerID)
            .limit(to: 1)
            .getDocuments()

        return !snap.documents.isEmpty
    }

    /// ラウンドを追加する
    func addGameRound(_ round: GameRound) async throws {
        let col = db.collection("gameRecords")
            .document(round.gameRecordID)
            .collection("gameResults")
            .document(round.gameResultID)
            .collection("gameRounds")
        let ref = round.id.flatMap { col.document($0) } ?? col.document()
        try ref.setData(from: round)
    }

    /// ラウンド一覧を取得する
    func fetchGameRounds(
        for recordID: String,
        resultID: String
    ) async throws -> [GameRound] {
        let snap = try await db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)
            .collection("gameRounds")
            .order(by: "roundNumber")
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: GameRound.self) }
    }

    /// ラウンド一覧の更新を購読する
    @discardableResult
    func subscribeGameRounds(
        for recordID: String,
        resultID: String,
        onUpdate: @escaping ([GameRound]) -> Void
    ) -> ListenerRegistration {

        guard !recordID.isEmpty, !resultID.isEmpty else {
            onUpdate([])
            return NoopListenerRegistration()
        }

        return db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)
            .collection("gameRounds")
            .order(by: "roundNumber")
            .addSnapshotListener { snap, error in
                if let error = error {
                    print("Firestore subscribeGameRounds エラー:", error)
                    return
                }
                let list = snap?.documents.compactMap {
                    try? $0.data(as: GameRound.self)
                } ?? []
                onUpdate(list)
            }
    }

    /// ラウンドと関連スコアを削除する
    func deleteGameRound(
        id: String,
        recordID: String,
        resultID: String
    ) async throws {
        let ref = db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)
            .collection("gameRounds")
            .document(id)
        let scoresSnap = try await ref.collection("scores").getDocuments()
        for scoreDoc in scoresSnap.documents {
            try await scoreDoc.reference.delete()
        }
        try await ref.delete()
    }

    /// スコアを追加する
    func addScore(_ score: Score) async throws {
        let col = db.collection("gameRecords")
            .document(score.gameRecordID)
            .collection("gameResults")
            .document(score.gameResultID)
            .collection("gameRounds")
            .document(score.gameRoundID)
            .collection("scores")
        let ref = score.id.flatMap { col.document($0) } ?? col.document()
        try ref.setData(from: score)
    }

    /// スコア一覧を取得する
    func fetchScores(
        for recordID: String,
        resultID: String,
        roundID: String
    ) async throws -> [Score] {
        let snap = try await db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)
            .collection("gameRounds")
            .document(roundID)
            .collection("scores")
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Score.self) }
    }

    /// スコア一覧の更新を購読する
    @discardableResult
    func subscribeScores(
        for recordID: String,
        resultID: String,
        roundID: String,
        onUpdate: @escaping ([Score]) -> Void
    ) -> ListenerRegistration {

        guard !recordID.isEmpty, !resultID.isEmpty, !roundID.isEmpty else {
            onUpdate([])
            return NoopListenerRegistration()
        }

        return db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)
            .collection("gameRounds")
            .document(roundID)
            .collection("scores")
            .addSnapshotListener { snap, error in
                if let error = error {
                    print("Firestore subscribeScores エラー:", error)
                    return
                }
                let list = snap?.documents.compactMap {
                    try? $0.data(as: Score.self)
                } ?? []
                onUpdate(list)
            }
    }

    /// スコアを削除する
    func deleteScore(
        id: String,
        recordID: String,
        resultID: String,
        roundID: String
    ) async throws {
        try await db.collection("gameRecords")
            .document(recordID)
            .collection("gameResults")
            .document(resultID)
            .collection("gameRounds")
            .document(roundID)
            .collection("scores")
            .document(id)
            .delete()
    }
}
