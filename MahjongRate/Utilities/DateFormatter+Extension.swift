//
//  DateFormatter+Extension.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation

/// 日付表示用のフォーマッタを提供する拡張
extension DateFormatter {
    /// 日本語の長い日付表記
    static let japaneseLongFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年MM月dd日 (EEE)"
        return formatter
    }()

    /// 日本語の短い日付表記
    static let japaneseShortFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}
