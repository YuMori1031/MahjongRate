//
//  AddGameRecordView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI

/// 対局記録を新規作成する画面
struct AddGameRecordView: View {
    /// ストレージViewModel
    @ObservedObject private var vm = StorageViewModel.shared
    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 入力中のタイトル
    @State private var title: String = ""
    /// 入力中の説明
    @State private var description: String = ""
    /// 上限到達アラート表示フラグ
    @State private var showLimitAlert = false

    /// 作成可能かどうか
    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasReachedRecordLimit
    }

    /// 記録数の上限に達しているか
    private var hasReachedRecordLimit: Bool {
        vm.gameRecords.count >= 50
    }

    /// 画面の本体
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 8) {
                    Text("記録概要")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Divider()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("タイトル")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("例：自宅麻雀", text: $title)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("説明コメント（任意）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("例：半荘赤ドラあり", text: $description)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .disableAutocorrection(true)
                }

                if hasReachedRecordLimit {
                    Text("記録は最大50件まで作成できます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button {
                        createRecord()
                    } label: {
                        Text("作成")
                            .font(.headline)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(canCreate ? Color.blue : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(24)
                            .shadow(radius: canCreate ? 3 : 0)
                    }
                    .disabled(!canCreate)
                    Spacer()
                }
                .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .navigationTitle("新規記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .alert("上限に達しました", isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("記録は最大50件まで作成できます。")
            }
        }
    }

    /// 対局記録を作成して閉じる
    private func createRecord() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            assertionFailure("createRecord called with empty title")
            return
        }
        guard !hasReachedRecordLimit else {
            showLimitAlert = true
            return
        }

        vm.addGameRecord(
            date: Date(),
            title: trimmedTitle,
            description: description.isEmpty ? nil : description
        )

        dismiss()
    }
}

#Preview {
    NavigationStack {
        AddGameRecordView()
    }
}
