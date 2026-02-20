//
//  GameRecord.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// 対局記録の基本情報を表すデータモデル
struct GameRecord: Identifiable, Codable, Hashable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?

    /// 対局日
    var date: Date
    /// 対局タイトル
    var title: String
    /// 補足説明
    var description: String?
    /// 作成者のUID
    var createdBy: String
    /// 参加メンバーのUID一覧
    var memberIDs: [String]
    /// 参加用の招待コード
    var inviteCode: String?
    /// 更新日時
    var updatedAt: Timestamp?
}
