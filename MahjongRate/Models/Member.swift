//
//  Member.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseFirestore

/// メンバー情報を表すデータモデル
struct Member: Identifiable, Codable, Hashable {
    /// FirestoreのドキュメントID
    @DocumentID var id: String?
    /// 表示名
    var name: String
    /// メールアドレス
    var email: String?
    /// アイコンの公開URL
    var iconURL: String?
    /// ストレージ内のパス
    var iconPath: String?
}
