//
//  AuthErrorMapper.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import FirebaseAuth

/// 認証エラーを日本語メッセージに変換するユーティリティ
enum AuthErrorMapper {
    /// エラーに対応する表示メッセージを返す
    static func message(for error: Error) -> String {
        let nsErr = error as NSError

        if nsErr.domain == "AuthViewModel" {
            return nsErr.localizedDescription
        }

        if let code = AuthErrorCode(rawValue: nsErr.code) {
            switch code {
            case .invalidEmail:
                return "メールアドレスの形式が正しくありません"
            case .userNotFound:
                return "アカウントが見つかりません"
            case .wrongPassword:
                return "パスワードが正しくありません"
            case .networkError:
                return "ネットワーク接続に失敗しました"
            case .userDisabled:
                return "このアカウントは無効化されています"
            case .tooManyRequests:
                return "リクエストが多すぎます。しばらくしてから再度お試しください"
            case .weakPassword:
                return "パスワードは6文字以上で設定してください"
            case .emailAlreadyInUse:
                return "このメールアドレスは既に使われています"
            case .internalError:
                return "内部エラーが発生しました。時間をおいて再度お試しください"
            default:
                return "認証に失敗しました。入力情報をご確認ください"
            }
        }

        return "認証に失敗しました。入力情報をご確認ください"
    }
}
