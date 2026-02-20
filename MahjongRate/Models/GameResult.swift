//
//  GameResult.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// 対局セッションの結果情報を表すデータモデル
struct GameResult: Identifiable, Codable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?
    /// 親となる対局記録ID
    var gameRecordID: String
    /// 対局日
    var date: Date
    /// セッション名
    var title: String
    /// レート
    var rate: Double
    /// 原点
    var basePoints: Int
    /// 参加プレイヤーID一覧
    var playerIDs: [String] = []
    /// 更新日時
    var updatedAt: Timestamp?

    /// 対局結果を生成する
    init(
        id: String? = nil,
        gameRecordID: String,
        date: Date,
        title: String,
        rate: Double,
        basePoints: Int,
        playerIDs: [String] = [],
        updatedAt: Timestamp? = nil
    ) {
        self.id = id
        self.gameRecordID = gameRecordID
        self.date = date
        self.title = title
        self.rate = rate
        self.basePoints = basePoints
        self.playerIDs = playerIDs
        self.updatedAt = updatedAt
    }
}
