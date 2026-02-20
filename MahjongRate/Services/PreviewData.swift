//
//  PreviewData.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// プレビュー用のダミーデータを提供するユーティリティ
enum PreviewData {
    /// プレビュー用ユーザーID
    static let currentUserID = "preview-user"
    /// プレビュー用レコードID
    static let recordID = "record123"
    /// プレビュー用セッションID
    static let resultID = "session1"

    /// プレビュー用対局記録一覧
    static let gameRecords: [GameRecord] = [
        GameRecord(
            id: "preview-admin-1",
            date: Date(),
            title: "自宅麻雀 夜の部",
            description: "連盟ルール 半荘戦",
            createdBy: currentUserID,
            memberIDs: [currentUserID, "user456", "user789", "user999", "user888"],
            inviteCode: "ABCD1234",
            updatedAt: Timestamp(date: Date().addingTimeInterval(-3600))
        ),
        GameRecord(
            id: "preview-admin-2",
            date: Date().addingTimeInterval(-86400 * 3),
            title: "会社メンバー対局",
            description: "3半荘",
            createdBy: currentUserID,
            memberIDs: [currentUserID, "user456", "user789"],
            inviteCode: "EFGH5678",
            updatedAt: nil
        ),
        GameRecord(
            id: "preview-member-1",
            date: Date().addingTimeInterval(-86400 * 12),
            title: "オンライン大会予選",
            description: "予選リーグ B組",
            createdBy: "other-user-1",
            memberIDs: [currentUserID, "other-user-1", "user999"],
            inviteCode: "WXYZ9012",
            updatedAt: Timestamp(date: Date().addingTimeInterval(-86400))
        ),
        GameRecord(
            id: "preview-member-2",
            date: Date().addingTimeInterval(-86400 * 30),
            title: "雀荘フリー対局",
            description: nil,
            createdBy: "owner-999",
            memberIDs: [currentUserID, "owner-999"],
            inviteCode: "LMNO3456",
            updatedAt: nil
        )
    ]

    /// 月別にグルーピングした対局記録
    static var groupedRecords: [String: [GameRecord]] {
        Dictionary(grouping: gameRecords) { r in
            let df = DateFormatter()
            df.dateFormat = "yyyy年MM月"
            let baseDate: Date = r.updatedAt?.dateValue() ?? r.date
            return df.string(from: baseDate)
        }
    }

    /// プレビュー用メンバー一覧
    static let previewMembers: [Member] = [
        Member(id: currentUserID, name: "自分"),
        Member(id: "user456", name: "太郎"),
        Member(id: "user789", name: "花子"),
        Member(id: "user999", name: "次郎"),
        Member(id: "user888", name: "三郎")
    ]

    /// 詳細画面用の対局記録
    static let previewDetailRecord: GameRecord = GameRecord(
        id: recordID,
        date: Date(),
        title: "自宅麻雀",
        description: "友人と集まってのテストプレイ（プレビュー）",
        createdBy: currentUserID,
        memberIDs: [currentUserID, "user456", "user789", "user999", "user888"],
        inviteCode: "ABCD2345",
        updatedAt: nil
    )

    /// プレビュー用セッション一覧
    static let previewGameResults: [GameResult] = [
        GameResult(
            id: resultID,
            gameRecordID: recordID,
            date: Date(),
            title: "半荘1回目",
            rate: 50.0,
            basePoints: 25000,
            playerIDs: ["p1", "p2", "p3", "p4", "p5"],
            updatedAt: nil
        )
    ]

    /// プレビュー用プレイヤー一覧
    static let players: [Player] = [
        Player(id: "p1", name: "長い名前のプレイヤーA（テスト）"),
        Player(id: "p2", name: "プレイヤーB"),
        Player(id: "p3", name: "プレイヤーC"),
        Player(id: "p4", name: "プレイヤーD"),
        Player(id: "p5", name: "プレイヤーE")
    ]

    /// 画面全体で使う対局結果
    static let gameResults: [GameResult] = previewGameResults

    /// プレビュー用ラウンド一覧
    static let rounds: [GameRound] = (1...12).map { no in
        GameRound(
            id: "r\(no)",
            gameRecordID: recordID,
            gameResultID: resultID,
            roundNumber: no
        )
    }

    /// ラウンドIDごとのスコア一覧
    static let scoresByRoundID: [String: [Score]] = {
        var dict: [String: [Score]] = [:]

        let pids = ["p1", "p2", "p3", "p4", "p5"]

        for no in 1...12 {
            let rid = "r\(no)"

            let restingIndex = (no - 1) % pids.count

            var scores: [Score] = []

            for (idx, pid) in pids.enumerated() {
                let isRest = (idx == restingIndex)
                let points: Int
                if isRest {
                    points = 0
                } else {
                    let base = [120, 40, -30, -80, 10]
                    points = base[(idx + no) % base.count]
                }

                scores.append(
                    Score(
                        id: "\(rid)-\(pid)",
                        gameRecordID: recordID,
                        gameResultID: resultID,
                        gameRoundID: rid,
                        playerID: pid,
                        points: points,
                        isResting: isRest,
                        updatedAt: nil
                    )
                )
            }

            dict[rid] = scores
        }

        return dict
    }()
}
