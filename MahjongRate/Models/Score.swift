//
//  Score.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// 1局のスコア情報を表すデータモデル
struct Score: Identifiable, Codable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?
    /// 親となる対局記録ID
    var gameRecordID: String
    /// 親となるセッションID
    var gameResultID: String
    /// 親となるラウンドID
    var gameRoundID: String
    /// 対象プレイヤーID
    var playerID: String
    /// 得点
    var points: Int
    /// 休み判定
    var isResting: Bool
    /// 更新日時
    @ServerTimestamp var updatedAt: Timestamp?
}
