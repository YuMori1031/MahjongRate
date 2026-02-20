//
//  ContentView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI
import FirebaseAuth
import FirebaseCore

/// 対局記録の一覧を表示するメイン画面
struct ContentView: View {
    /// ストレージViewModel
    @StateObject private var vm = StorageViewModel.shared

    /// ナビゲーションのパス
    @Binding var path: [GameRecord]

    /// 新規記録シート表示フラグ
    @State private var showingAddGameView = false
    /// 退出アラート表示フラグ
    @State private var showingDeleteAlert = false
    /// 退出対象の記録ID
    @State private var gameRecordToDeleteID: String?
    /// 招待参加シート表示フラグ
    @State private var showingJoinGameView = false
    /// 記録上限アラート表示フラグ
    @State private var showingRecordLimitAlert = false

    /// サイドメニュー表示フラグ
    @Binding var isMenuOpen: Bool

    /// プロフィール画面遷移フラグ
    @Binding var navigateToProfile: Bool

    /// アカウント設定画面遷移フラグ
    @Binding var navigateToAccountSettings: Bool

    /// フローティングメニュー表示フラグ
    @State private var isFabMenuPresented = false

    /// 現在のユーザーID
    private var currentUserID: String? {
        #if DEBUG
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview {
            return "preview-user"
        }
        #endif
        return Auth.auth().currentUser?.uid
    }

    /// 画面の本体
    var body: some View {
        ZStack {
            ZStack {
                recordListView

                if path.isEmpty {
                    floatingButton
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("記録一覧")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation { isMenuOpen.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            .task {
                let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
                if !isPreview {
                    vm.startMyGameRecords()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddGameView) {
            AddGameRecordView()
        }
        .sheet(isPresented: $showingJoinGameView) {
            NavigationStack {
                JoinGameRecordView()
            }
        }
        .alert("上限に達しました", isPresented: $showingRecordLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("記録は最大50件まで作成できます。")
        }
        .alert("この記録から退出しますか？", isPresented: $showingDeleteAlert) {
            Button("退出", role: .destructive) {
                if let id = gameRecordToDeleteID,
                   let record = vm.gameRecords.first(where: { $0.id == id }) {
                    vm.leaveOrDeleteGameRecord(record)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            if let id = gameRecordToDeleteID,
               let record = vm.gameRecords.first(where: { $0.id == id }) {
                Text(deleteAlertMessage(for: record))
            } else {
                Text("この操作を行うと、記録一覧からこの項目が削除されます。")
            }
        }
        .loadingOverlay(
            isPresented: vm.isLoadingMyGameRecords && path.isEmpty,
            message: "読み込み中…"
        )
    }

    /// 記録一覧の表示
    @ViewBuilder
    private var recordListView: some View {
        if vm.gameRecords.isEmpty {
            emptyStateView
        } else {
            List {
                let sectionKeys = groupedRecords.keys.sorted(by: >)
                ForEach(sectionKeys, id: \.self) { key in
                    Section(header: Text(key)) {
                        let records = groupedRecords[key] ?? []

                        let sortedRecords = records.sorted { lhs, rhs in
                            let lDate = lhs.updatedAt?.dateValue() ?? lhs.date
                            let rDate = rhs.updatedAt?.dateValue() ?? rhs.date
                            return lDate > rDate
                        }

                        ForEach(sortedRecords) { record in
                            NavigationLink(value: record) {
                                rowView(for: record)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    gameRecordToDeleteID = record.id
                                    showingDeleteAlert = true
                                } label: {
                                    Label("退出", systemImage: "person.fill.xmark")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            .animation(.default, value: vm.gameRecords)
        }
    }

    /// 記録行の表示
    @ViewBuilder
    private func rowView(for record: GameRecord) -> some View {
        let uid = currentUserID
        let isCreator = (record.createdBy == uid)

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCreator ? Color.yellow : Color.blue)

                VStack(spacing: 2) {
                    Image(systemName: isCreator ? "crown.fill" : "person.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)

                    Text(isCreator ? "管理者" : "メンバー")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isCreator ? .red : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title.isEmpty ? "タイトルなし" : record.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let desc = record.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let updatedAt = record.updatedAt {
                    let updatedDate = updatedAt.dateValue()
                    Text("最終更新: \(updatedDate, formatter: DateFormatter.japaneseShortFormat)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("対局結果なし")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("参加者")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("\(record.memberIDs.count)人")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.gray.opacity(0.15))
                    )
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 6)
    }

    /// フローティングボタン
    private var floatingButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    isFabMenuPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                        .accessibilityLabel("記録を追加")
                }
                .padding(24)
                .confirmationDialog(
                    "記録の追加方法を選択",
                    isPresented: $isFabMenuPresented
                ) {
                    Button("新しく記録を作成") {
                        if vm.gameRecords.count >= 50 {
                            showingRecordLimitAlert = true
                        } else {
                            showingAddGameView = true
                        }
                    }
                    Button("招待コードで参加") {
                        showingJoinGameView = true
                    }
                } message: {
                    Text("どの方法で記録を追加しますか？")
                }
            }
        }
    }

    /// 記録未作成時の表示
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("まだ記録がありません")
                .font(.headline)

            Text(
                """
                右下のボタンから
                記録の作成や参加ができます。
                """
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 退出アラートの文言を生成する
    private func deleteAlertMessage(for record: GameRecord) -> String {
        let title = record.title.isEmpty ? "タイトルなし" : record.title
        let uid = currentUserID

        guard let uid else {
            return """
            タイトル: \(title)

            記録一覧から削除されます。
            """
        }

        let isCreator = (record.createdBy == uid)
        let otherMembers = record.memberIDs.filter { $0 != uid }
        let hasOthers = !otherMembers.isEmpty

        if !hasOthers {
            return """
            タイトル: \(title)

            記録一覧から削除されます。
            他のメンバーがいないため、
            この記録は完全に削除されます。
            """
        }

        if isCreator {
            return """
            タイトル: \(title)

            記録一覧から削除されます。
            退出すると管理者の役割は、
            残っているメンバーに引き継がれます。
            """
        }

        return """
        タイトル: \(title)

        記録一覧から削除されます。
        ほかのメンバーの記録には影響しません。
        """
    }

    /// 月別にグルーピングした対局記録
    private var groupedRecords: [String: [GameRecord]] {
        Dictionary(grouping: vm.gameRecords) { r in
            let df = DateFormatter()
            df.dateFormat = "yyyy年MM月"
            let baseDate: Date = r.updatedAt?.dateValue() ?? r.date
            return df.string(from: baseDate)
        }
    }
}

#Preview {
    let vm = StorageViewModel.shared
    vm.gameRecords = PreviewData.gameRecords

    return NavigationStack {
        ContentView(
            path: .constant([]),
            isMenuOpen: .constant(false),
            navigateToProfile: .constant(false),
            navigateToAccountSettings: .constant(false)
        )
    }
}
