//
//  GameRound.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// 1局分のラウンド情報を表すデータモデル
struct GameRound: Identifiable, Codable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?
    /// 親となる対局記録ID
    var gameRecordID: String
    /// 親となるセッションID
    var gameResultID: String
    /// 局番号
    var roundNumber: Int
}
