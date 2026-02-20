//
//  PendingMember.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/13.
//

import Foundation
import FirebaseFirestore

/// 参加申請中メンバーを表すデータモデル
struct PendingMember: Identifiable, Codable, Hashable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?
    /// 申請者のUID
    var memberID: String
    /// 申請日時
    var requestedAt: Timestamp?
}
