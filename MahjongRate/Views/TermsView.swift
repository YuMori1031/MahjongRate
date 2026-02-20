//
//  TermsView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI

/// 利用規約の表示画面
struct TermsView: View {
    @Environment(\.dismiss) private var dismiss

    private let termsText = """
    利用規約（雀レート）

    この利用規約（以下「本規約」）は、雀レート（以下「本アプリ」）の利用条件を定めるものです。

    第1条（適用）
    本規約は、ユーザーと開発者との間の本アプリ利用に関する一切の関係に適用されます。

    第2条（利用登録）
    本アプリの一部機能はアカウント登録が必要です。登録情報は正確に入力してください。

    第3条（禁止事項）
    ユーザーは、以下の行為をしてはなりません。
    ・法令または公序良俗に違反する行為
    ・不正アクセスまたはそれを助長する行為
    ・他者になりすます行為
    ・本アプリの運営を妨げる行為
    ・その他、開発者が不適切と判断する行為

    第4条（ユーザーコンテンツ）
    ユーザーが本アプリに保存した記録・内容について、その責任はユーザー自身が負うものとします。

    第5条（免責事項）
    開発者は、本アプリの提供にあたり万全を期していますが、データの損失や不具合等について一切の責任を負いません。

    第6条（サービスの変更・終了）
    開発者は、予告なく本アプリの内容変更または提供終了を行うことがあります。

    第7条（利用規約の変更）
    本規約は必要に応じて変更されることがあります。

    第8条（お問い合わせ）
    お問い合わせは以下までご連絡ください。
    Web: https://www.yumori.dev/#contact
    """

    var body: some View {
        ScrollView {
            Text(termsText)
                .font(.footnote)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle("利用規約")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
    }
}
