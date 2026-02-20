//
//  EmailValidator.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation

/// メールアドレス形式を判定するユーティリティ
enum EmailValidator {
    /// メールアドレスが妥当な形式か判定する
    static func isValid(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
