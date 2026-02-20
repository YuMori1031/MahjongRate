//
//  Player.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// プレイヤー情報を表すデータモデル
struct Player: Identifiable, Codable, Hashable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?
    /// 表示名
    var name: String
    /// 作成日時
    var createdAt: Timestamp? = nil

    /// プレイヤー情報を生成する
    init(id: String? = nil, name: String, createdAt: Timestamp? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
