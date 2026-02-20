//
//  EditSessionView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI

/// 対局結果を編集する画面
struct EditSessionView: View {
   
    /// 対象の対局記録ID
    let recordID: String
    /// 編集対象のセッション
    let session: GameResult
    /// 編集可否
    let canEdit: Bool
    /// レート選択肢
    let rateOptions: [Double]
    /// 原点選択肢
    let pointsOptions: [Int]

    /// 保存処理を呼び出すクロージャ
    let onSave: (_ title: String, _ date: Date, _ rate: Double, _ basePoints: Int, _ playerIDs: [String]) async throws -> Void

    /// プレイヤー辞書
    let playerByID: [String: Player]

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 入力中のタイトル
    @State private var title: String
    /// 入力中の日付
    @State private var date: Date
    /// 入力中のレート
    @State private var rate: Double
    /// 入力中の原点
    @State private var basePoints: Int
    /// 選択中のプレイヤーID一覧
    @State private var selectedPlayerIDs: [String]

    /// 保存処理中フラグ
    @State private var isSaving: Bool = false
    /// アラート表示フラグ
    @State private var showAlert: Bool = false
    /// アラートメッセージ
    @State private var alertMessage: String = ""
    /// プレイヤー選択シート表示フラグ
    @State private var isShowingPlayerPicker: Bool = false

    /// 初期値を注入して初期化する
    init(
        recordID: String,
        session: GameResult,
        canEdit: Bool,
        rateOptions: [Double],
        pointsOptions: [Int],
        onSave: @escaping (_ title: String, _ date: Date, _ rate: Double, _ basePoints: Int, _ playerIDs: [String]) async throws -> Void,
        playerByID: [String: Player]
    ) {
        self.recordID = recordID
        self.session = session
        self.canEdit = canEdit
        self.rateOptions = rateOptions
        self.pointsOptions = pointsOptions
        self.onSave = onSave
        self.playerByID = playerByID

        _title = State(initialValue: session.title)
        _date = State(initialValue: session.date)
        _rate = State(initialValue: session.rate)
        _basePoints = State(initialValue: session.basePoints)
        _selectedPlayerIDs = State(initialValue: session.playerIDs)
    }

    /// トリム済みタイトル
    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// プレビュー実行中かどうか
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// 保存可能かどうか
    private var canSave: Bool {
        guard canEdit, !isSaving else { return false }
        guard !trimmedTitle.isEmpty else { return false }
        guard !selectedPlayerIDs.isEmpty else { return false }
        guard selectedPlayerIDs.count <= 10 else { return false }
        return true
    }

    /// 画面の本体
    var body: some View {
        if isPreview {
            baseView
        } else {
            baseView
                .sheet(isPresented: $isShowingPlayerPicker) {
                    NavigationStack {
                        PlayerPickerView(
                            recordID: recordID,
                            selectedIDs: $selectedPlayerIDs
                        )
                    }
                }
        }
    }

    private var baseView: some View {
        NavigationStack {
            VStack {
                Form {
                    Section(header: Text("対局情報")) {
                        TextField("タイトル", text: $title)
                            .disabled(!canEdit)

                        HStack {
                            Image(systemName: "calendar").foregroundColor(.blue)
                            DatePicker("日付", selection: $date, displayedComponents: .date)
                                .disabled(!canEdit)
                        }

                        HStack {
                            Image(systemName: "dollarsign.circle").foregroundColor(.green)
                            Picker("レート", selection: $rate) {
                                ForEach(rateOptions, id: \.self) { r in
                                    Text("\(Int(r))ポイント").tag(r)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .disabled(!canEdit)
                        }

                        HStack {
                            Image(systemName: "target").foregroundColor(.orange)
                            Picker("原点", selection: $basePoints) {
                                ForEach(pointsOptions, id: \.self) { p in
                                    Text("\(p)点").tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .disabled(!canEdit)
                        }
                    }

                    Section(header: Text("プレイヤー")) {
                        if selectedPlayerIDs.isEmpty {
                            Text("プレイヤーが未選択です。下のボタンから選択してください。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(selectedPlayerIDs, id: \.self) { pid in
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.secondary)

                                    Text(playerByID[pid]?.name ?? pid)

                                    Spacer()
                                }
                            }
                            .onDelete { offsets in
                                guard canEdit else { return }
                                selectedPlayerIDs.remove(atOffsets: offsets)
                            }
                        }

                        Button {
                            guard canEdit else { return }
                            isShowingPlayerPicker = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                Text("プレイヤーを選択・追加")
                                Spacer()
                            }
                        }
                        .disabled(!canEdit)

                        if selectedPlayerIDs.count > 5 {
                            Text("プレイヤーは最大10人までです。余分なプレイヤーを削除してください。")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    if !canEdit {
                        Section {
                            Text("編集/削除は、この記録の参加メンバーのみ可能です。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .navigationTitle("対局結果を編集")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                            .disabled(isSaving)
                    }
                }
                Button(isSaving ? "保存中…" : "保存") {
                    Task { await saveTapped() }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .background(canSave ? Color.blue : Color.gray.opacity(0.3))
                .cornerRadius(8)
                .padding()
                .disabled(!canSave)
        .alert("エラー", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
            }
        }
    }

    /// 保存処理を実行する
    @MainActor
    private func saveTapped() async {
        guard canEdit else { return }

        guard !trimmedTitle.isEmpty else {
            alertMessage = "タイトルを入力してください。"
            showAlert = true
            return
        }
        guard !selectedPlayerIDs.isEmpty else {
            alertMessage = "プレイヤーを1人以上選択してください。"
            showAlert = true
            return
        }
        guard selectedPlayerIDs.count <= 10 else {
            alertMessage = "プレイヤーは最大10人までです。"
            showAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(trimmedTitle, date, rate, basePoints, selectedPlayerIDs)
            dismiss()
        } catch {
            alertMessage = "保存に失敗しました: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    EditSessionView(
        recordID: "",
        session: GameResult(
            gameRecordID: "",
            date: .now,
            title: "",
            rate: 1000,
            basePoints: 25000,
            playerIDs: []
        ),
        canEdit: true,
        rateOptions: [1000],
        pointsOptions: [25000],
        onSave: { _, _, _, _, _ in },
        playerByID: [:]
    )
}
