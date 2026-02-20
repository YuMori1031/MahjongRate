//
//  GameRecordDetailView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import CoreImage.CIFilterBuiltins

/// 対局記録の詳細を表示する画面
struct GameRecordDetailView: View {

    /// 表示対象の記録
    let record: GameRecord

    /// ストレージViewModel
    @ObservedObject private var vm = StorageViewModel.shared

    /// 画面上で表示する最新の記録
    @State private var liveRecord: GameRecord

    /// 記録の購読リスナー
    @State private var recordListener: ListenerRegistration? = nil

    /// プレイヤー一覧の購読リスナー
    @State private var playersListener: ListenerRegistration? = nil
    /// 登録済みプレイヤー数
    @State private var playerCount: Int = 0

    /// 招待コードシートの表示状態
    @State private var isShowingInviteSheet = false
    /// 記録のリアルタイム更新を有効にするかどうか
    private let isLiveUpdateEnabled = true
    /// 記録編集シートの表示状態
    @State private var isShowingEditSheet = false
    /// プレイヤー一覧シートの表示状態
    @State private var isShowingPlayerListSheet = false
    /// 参加メンバー管理シートの表示状態
    @State private var isShowingMemberManagementSheet = false
    /// プレビュー用に管理者判定を上書きするUID
    private let previewAdminUID: String?

    /// 参加申請中メンバーの購読リスナー
    @State private var pendingMembersListener: ListenerRegistration? = nil
    /// 参加申請中メンバー一覧
    @State private var pendingMembers: [PendingMember] = []

    /// 初期値を注入して初期化する
    init(record: GameRecord, previewAdminUID: String? = nil) {
        self.record = record
        self.previewAdminUID = previewAdminUID
        _liveRecord = State(initialValue: record)
    }

    /// 自分のUID
    private var myUID: String? { Auth.auth().currentUser?.uid }

    /// 管理者のUID
    private var ownerUID: String? { liveRecord.createdBy }

    /// 管理者かどうか
    private var isAdmin: Bool {
        guard let ownerUID else { return false }
        if let previewAdminUID {
            return previewAdminUID == ownerUID
        }
        guard let myUID else { return false }
        return myUID == ownerUID
    }


    /// 画面の本体
    var body: some View {
        content
            .sheet(isPresented: $isShowingInviteSheet) {
                NavigationStack {
                    InviteView(inviteCode: liveRecord.inviteCode)
                }
            }
            .sheet(isPresented: $isShowingPlayerListSheet) {
                if let id = liveRecord.id ?? record.id {
                    NavigationStack {
                        PlayerListView(recordID: id)
                    }
                } else {
                    NavigationStack {
                        Text("recordID が取得できませんでした。")
                            .foregroundColor(.secondary)
                            .navigationTitle("エラー")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .sheet(isPresented: $isShowingMemberManagementSheet) {
                if let recordID = liveRecord.id ?? record.id {
                    NavigationStack {
                        MemberManagementSheet(
                            recordID: recordID,
                            memberIDs: liveRecord.memberIDs,
                            pendingMembers: pendingMembers,
                            ownerUID: ownerUID,
                            myUID: myUID,
                            isAdmin: isAdmin,
                            onApprove: { pending in
                                Task { await approvePendingMember(pending) }
                            },
                            onReject: { pending in
                                Task { await rejectPendingMember(pending) }
                            },
                            onRemove: { member in
                                Task { await removeMemberFromRecord(member) }
                            }
                        )
                    }
                } else {
                    NavigationStack {
                        Text("recordID が取得できませんでした。")
                            .foregroundColor(.secondary)
                            .navigationTitle("エラー")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .sheet(isPresented: $isShowingEditSheet) {
                NavigationStack {
                    EditRecordSheet(
                        record: liveRecord,
                        canEdit: isAdmin,
                        onSave: { title, desc in
                            Task {
                                try await updateRecord(title: title, description: desc)
                            }
                        }
                    )
                }
            }
    }

    /// 画面の土台
    private var content: some View {
        List {
            Section(header: Text("概要")) {
                overviewCard
            }

            sessionLinkSection

            playerLinkSection

            memberManagementLinkSection
        }
        .navigationTitle(liveRecord.title.isEmpty ? "タイトルなし" : liveRecord.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Text("編集")
                    }
                }
            }
        }
        .task {
            if let id = liveRecord.id {
                vm.startGameResults(for: id)
            }

            if vm.members.isEmpty {
                vm.startMembers()
            }

            if isLiveUpdateEnabled {
                startRecordListenerIfNeeded()
                startPlayersListenerIfNeeded()
                startPendingMembersListenerIfNeeded()
            }
        }
        .onDisappear {
            recordListener?.remove()
            recordListener = nil
            playersListener?.remove()
            playersListener = nil
            pendingMembersListener?.remove()
            pendingMembersListener = nil
        }
        .onChange(of: isShowingInviteSheet) { _, isPresented in
            guard isLiveUpdateEnabled else { return }
            if isPresented {
                recordListener?.remove()
                recordListener = nil
            } else {
                startRecordListenerIfNeeded()
            }
        }
        .onChange(of: isShowingEditSheet) { _, isPresented in
            guard isLiveUpdateEnabled else { return }
            if isPresented {
                recordListener?.remove()
                recordListener = nil
            } else {
                startRecordListenerIfNeeded()
            }
        }
    }

    /// 記録の購読を開始する
    private func startRecordListenerIfNeeded() {
        guard isLiveUpdateEnabled else { return }
        guard recordListener == nil else { return }

        guard let recordID = record.id ?? liveRecord.id else {
            print("❌ startRecordListenerIfNeeded: recordID がありません")
            return
        }

        let ref = Firestore.firestore().collection("gameRecords").document(recordID)

        recordListener = ref.addSnapshotListener { snap, error in
            if let error = error {
                print("❌ record listener error:", error)
                return
            }
            guard let snap, snap.exists else { return }

            do {
                let updated = try snap.data(as: GameRecord.self)
                DispatchQueue.main.async {
                    self.liveRecord = updated
                }
            } catch {
                print("❌ decode GameRecord error:", error)
            }
        }
    }

    /// プレイヤー一覧の購読を開始する
    private func startPlayersListenerIfNeeded() {
        guard playersListener == nil else { return }

        guard let recordID = record.id ?? liveRecord.id else {
            print("❌ startPlayersListenerIfNeeded: recordID がありません")
            return
        }

        let ref = Firestore.firestore()
            .collection("gameRecords")
            .document(recordID)
            .collection("players")

        playersListener = ref.addSnapshotListener { snap, error in
            if let error = error {
                print("❌ players listener error:", error)
                return
            }
            let count = snap?.documents.count ?? 0
            DispatchQueue.main.async {
                self.playerCount = count
            }
        }
    }

    /// 参加申請中メンバーの購読を開始する
    private func startPendingMembersListenerIfNeeded() {
        guard isAdmin else { return }
        guard pendingMembersListener == nil else { return }
        guard let recordID = record.id ?? liveRecord.id else {
            print("❌ startPendingMembersListenerIfNeeded: recordID がありません")
            return
        }

        let ref = Firestore.firestore()
            .collection("gameRecords")
            .document(recordID)
            .collection("pendingMembers")
            .order(by: "requestedAt", descending: true)

        pendingMembersListener = ref.addSnapshotListener { snap, error in
            if let error = error {
                print("❌ pendingMembers listener error:", error)
                return
            }

            let list = snap?.documents.compactMap {
                try? $0.data(as: PendingMember.self)
            } ?? []

            DispatchQueue.main.async {
                self.pendingMembers = list
            }
        }
    }

    /// 概要カード
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let desc = liveRecord.description, !desc.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text("最終更新日: \(liveRecord.date, formatter: DateFormatter.japaneseLongFormat)")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label("参加メンバー \(liveRecord.memberIDs.count) 人", systemImage: "person.3.fill")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let inviteCode = liveRecord.inviteCode, !inviteCode.isEmpty {
                Button {
                    isShowingInviteSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode")
                        Text("招待コードを表示")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(inviteCode)
                            .font(.caption2)
                            .monospaced()
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }


    /// 対局結果一覧へのリンク
    private var sessionLinkSection: some View {
        Section(header: Text("対局結果")) {
            NavigationLink {
                GameSessionListView(record: liveRecord)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("対局結果一覧を見る")
                    Text("登録済み: \(vm.gameResults.count)件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// プレイヤー一覧へのリンク
    private var playerLinkSection: some View {
        Section(header: Text("プレイヤー")) {
            if liveRecord.id == nil && record.id == nil {
                Text("プレイヤー情報を取得できませんでした。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button {
                    isShowingPlayerListSheet = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("プレイヤー一覧を見る")
                            .foregroundColor(.black)
                        Text("登録済み \(playerCount) 人")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    /// 参加メンバー一覧へのリンク
    private var memberManagementLinkSection: some View {
        Section(header: Text("参加メンバー")) {
            Button {
                isShowingMemberManagementSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("参加メンバー一覧を見る")
                        .foregroundColor(.black)
                    Text("参加中: \(liveRecord.memberIDs.count) 人")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 管理者バッジ
    private var ownerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
            Text("管理者")
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.orange.opacity(0.12)))
        .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 1))
        .accessibilityLabel("管理者")
    }

    /// 参加メンバーを取得する
    private var participantMembers: [Member] {
        vm.members
            .filter { member in
                guard let mid = member.id else { return false }
                return liveRecord.memberIDs.contains(mid)
            }
            .sorted { $0.name < $1.name }
    }


    /// 表示名を整形する
    private func displayName(for member: Member) -> String {
        guard let mid = member.id else { return member.name }
        if mid == myUID {
            return "\(member.name)（自分）"
        } else {
            return member.name
        }
    }

    /// 管理者かどうかを判定する
    private func isOwner(_ member: Member) -> Bool {
        guard let mid = member.id, let ownerUID else { return false }
        return mid == ownerUID
    }

    /// 削除ボタンを表示するかどうか
    private func shouldShowRemoveButton(for member: Member) -> Bool {
        guard isAdmin else { return false }
        guard let targetUID = member.id else { return false }
        guard let myUID else { return false }

        if targetUID == myUID { return false }

        if targetUID == ownerUID { return false }

        if liveRecord.memberIDs.count <= 1 { return false }

        return true
    }

    /// 記録情報を更新する
    @MainActor
    private func updateRecord(title: String, description: String?) async throws {
        guard isAdmin else { return }
        guard let recordID = liveRecord.id else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var data: [String: Any] = [
            "title": trimmedTitle,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let d = trimmedDesc, !d.isEmpty {
            data["description"] = d
        } else {
            data["description"] = FieldValue.delete()
        }

        try await Firestore.firestore()
            .collection("gameRecords")
            .document(recordID)
            .updateData(data)
    }

    /// メンバーを記録から削除する
    @MainActor
    private func removeMemberFromRecord(_ member: Member) async {
        guard isAdmin else { return }
        guard let recordID = liveRecord.id else { return }
        guard let targetUID = member.id else { return }
        guard let myUID else { return }

        guard targetUID != myUID else { return }

        guard liveRecord.memberIDs.count > 1 else { return }

        do {
            try await Firestore.firestore()
                .collection("gameRecords")
                .document(recordID)
                .updateData([
                    "memberIDs": FieldValue.arrayRemove([targetUID]),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("❌ removeMemberFromRecord error:", error)
        }
    }

    /// 参加申請を承認する
    @MainActor
    private func approvePendingMember(_ pending: PendingMember) async {
        guard isAdmin else { return }
        guard let recordID = liveRecord.id else { return }
        let targetUID = pending.memberID

        let db = Firestore.firestore()
        let recordRef = db.collection("gameRecords").document(recordID)
        let pendingRef = recordRef.collection("pendingMembers").document(targetUID)

        do {
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let current = try transaction.getDocument(recordRef)
                    var memberIDs = current.data()?["memberIDs"] as? [String] ?? []
                    if !memberIDs.contains(targetUID) {
                        memberIDs.append(targetUID)
                        transaction.updateData(
                            [
                                "memberIDs": memberIDs,
                                "updatedAt": FieldValue.serverTimestamp()
                            ],
                            forDocument: recordRef
                        )
                    }
                    transaction.deleteDocument(pendingRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                return nil
            }
        } catch {
            print("❌ approvePendingMember error:", error)
        }
    }

    /// 参加申請を却下する
    @MainActor
    private func rejectPendingMember(_ pending: PendingMember) async {
        guard isAdmin else { return }
        guard let recordID = liveRecord.id else { return }
        let targetUID = pending.memberID

        do {
            try await Firestore.firestore()
                .collection("gameRecords")
                .document(recordID)
                .collection("pendingMembers")
                .document(targetUID)
                .delete()
        } catch {
            print("❌ rejectPendingMember error:", error)
        }
    }
}

/// 参加メンバー管理シート
private struct MemberManagementSheet: View {
    let recordID: String
    let memberIDs: [String]
    let pendingMembers: [PendingMember]
    let ownerUID: String?
    let myUID: String?
    let isAdmin: Bool
    let onApprove: (PendingMember) -> Void
    let onReject: (PendingMember) -> Void
    let onRemove: (Member) -> Void

    @ObservedObject private var vm = StorageViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pendingApprove: PendingMember? = nil
    @State private var pendingRemove: Member? = nil
    @State private var isShowingApproveConfirm = false
    @State private var isShowingRemoveConfirm = false

    var body: some View {
        List {
            Section(header: Text("参加中メンバー")) {
                if approvedMembers.isEmpty {
                    Text("参加中のメンバーがいません。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(approvedMembers) { member in
                        HStack(spacing: 12) {
                            MemberIconView(iconURLString: member.iconURL)
                            HStack(spacing: 8) {
                                Text(displayName(for: member))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if isOwner(member) {
                                    ownerBadge
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if shouldAllowRemoveApproved(member) {
                                Button {
                                    pendingRemove = member
                                    isShowingRemoveConfirm = true
                                } label: {
                                    Label("削除", systemImage: "person.fill.xmark")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }

            if isAdmin {
                Section(header: Text("承認待ち")) {
                    if pendingMembersForDisplay.isEmpty {
                        Text("承認待ちの申請はありません。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(pendingMembersForDisplay) { item in
                            HStack(spacing: 12) {
                                MemberIconView(iconURLString: item.member?.iconURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text("参加申請中")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button("承認") {
                                    pendingApprove = item.pending
                                    isShowingApproveConfirm = true
                                }
                                .buttonStyle(.borderedProminent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                if let member = item.member {
                                    pendingRemove = member
                                } else {
                                    pendingRemove = Member(
                                        id: item.pending.memberID,
                                        name: item.displayName,
                                        email: nil,
                                        iconURL: nil,
                                        iconPath: nil
                                    )
                                }
                                isShowingRemoveConfirm = true
                            } label: {
                                Label("削除", systemImage: "person.fill.xmark")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        }
        .navigationTitle("参加メンバー一覧")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .alert(
            "このメンバーの参加を承認しますか？",
            isPresented: $isShowingApproveConfirm,
            presenting: pendingApprove
        ) { pending in
            Button("キャンセル", role: .cancel) { }
            Button("OK") {
                onApprove(pending)
            }
        }
        .alert(
            "このメンバーを削除しますか？",
            isPresented: $isShowingRemoveConfirm,
            presenting: pendingRemove
        ) { member in
            Button("キャンセル", role: .cancel) { }
            Button("削除") {
                if pendingMembers.contains(where: { $0.memberID == member.id }) {
                    if let pending = pendingMembers.first(where: { $0.memberID == member.id }) {
                        onReject(pending)
                    }
                } else {
                    onRemove(member)
                }
            }
        }
    }

    private var approvedMembers: [Member] {
        vm.members
            .filter { member in
                guard let mid = member.id else { return false }
                return memberIDs.contains(mid)
            }
            .sorted { $0.name < $1.name }
    }

    private var pendingMembersForDisplay: [PendingMemberDisplay] {
        pendingMembers.compactMap { pending in
            let member = vm.members.first { $0.id == pending.memberID }
            return PendingMemberDisplay(
                id: pending.id ?? pending.memberID,
                pending: pending,
                member: member
            )
        }
    }

    private func displayName(for member: Member) -> String {
        guard let mid = member.id else { return member.name }
        if mid == myUID {
            return "\(member.name)（自分）"
        } else {
            return member.name
        }
    }

    private func isOwner(_ member: Member) -> Bool {
        guard let mid = member.id, let ownerUID else { return false }
        return mid == ownerUID
    }

    private func shouldAllowRemoveApproved(_ member: Member) -> Bool {
        guard isAdmin else { return false }
        guard let targetUID = member.id else { return false }
        guard let myUID else { return false }
        if targetUID == ownerUID { return false }
        if targetUID == myUID { return false }
        if memberIDs.count <= 1 { return false }
        return true
    }

    private var ownerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
            Text("管理者")
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.orange.opacity(0.12)))
        .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 1))
        .accessibilityLabel("管理者")
    }
}

/// 参加申請中の表示用データ
private struct PendingMemberDisplay: Identifiable {
    let id: String
    let pending: PendingMember
    let member: Member?

    var displayName: String {
        member?.name ?? "ユーザー"
    }
}

/// 記録編集用シート
private struct EditRecordSheet: View {
    /// 編集対象の記録
    let record: GameRecord
    /// 編集可否
    let canEdit: Bool
    /// 保存処理を呼び出すクロージャ
    let onSave: (_ title: String, _ description: String?) -> Void

    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// 入力中のタイトル
    @State private var title: String
    /// 入力中の説明
    @State private var descriptionText: String
    /// 保存処理中フラグ
    @State private var isSaving: Bool = false
    /// エラーメッセージ
    @State private var errorMessage: String? = nil

    /// 初期値を注入して初期化する
    init(
        record: GameRecord,
        canEdit: Bool,
        onSave: @escaping (_ title: String, _ description: String?) -> Void
    ) {
        self.record = record
        self.canEdit = canEdit
        self.onSave = onSave
        _title = State(initialValue: record.title)
        _descriptionText = State(initialValue: record.description ?? "")
    }

    /// 保存可能かどうか
    private var canSave: Bool {
        guard canEdit else { return false }
        guard !isSaving else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 画面の本体
    var body: some View {
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
                    .disabled(!canEdit || isSaving)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("説明コメント（任意）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("例：半荘赤ドラあり", text: $descriptionText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .disableAutocorrection(true)
                    .disabled(!canEdit || isSaving)
            }

            if !canEdit {
                Text("この記録は管理者のみ編集できます")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button {
                    save()
                } label: {
                    Text(isSaving ? "保存中…" : "保存")
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(canSave ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(24)
                        .shadow(radius: canSave ? 3 : 0)
                }
                .disabled(!canSave)
                Spacer()
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .navigationTitle("記録を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
                    .disabled(isSaving)
            }
        }
    }

    /// 保存処理を実行する
    private func save() {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc: String? = trimmedDesc.isEmpty ? nil : trimmedDesc

        onSave(trimmedTitle, desc)
        dismiss()
        isSaving = false
    }
}

/// メンバーのアイコン表示
private struct MemberIconView: View {

    /// アイコンURL
    let iconURLString: String?

    /// 読み込み済み画像
    @State private var uiImage: UIImage? = nil
    /// 読み込み中フラグ
    @State private var isLoading: Bool = false

    /// 表示サイズ
    private let size: CGFloat = 34

    /// 画面の本体
    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        .task {
            await loadIfNeeded()
        }
    }

    /// アイコンを読み込む
    private func loadIfNeeded() async {
        let urlString = await MainActor.run { () -> String? in
            guard uiImage == nil, !isLoading else { return nil }
            guard let iconURLString, !iconURLString.isEmpty else { return nil }
            isLoading = true
            return iconURLString
        }
        guard let urlString else { return }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            if Task.isCancelled { return }
            let finalURL = try await resolveURL(urlString)
            let (data, _) = try await URLSession.shared.data(from: finalURL)
            if Task.isCancelled { return }
            guard let img = UIImage(data: data) else { return }
            await MainActor.run {
                uiImage = img
            }
        } catch {
        }
    }

    /// URLを解決する
    private func resolveURL(_ iconURLString: String) async throws -> URL {
        if iconURLString.hasPrefix("gs://") {
            let ref = Storage.storage().reference(forURL: iconURLString)
            return try await ref.downloadURL()
        } else if let url = URL(string: iconURLString) {
            return url
        } else {
            throw URLError(.badURL)
        }
    }
}

/// 招待コードを表示する画面
private struct InviteView: View {

    /// 招待コード
    let inviteCode: String?
    /// 画面を閉じるための環境値
    @Environment(\.dismiss) private var dismiss
    /// 生成済みのQRコード画像
    @State private var qrImage: UIImage? = nil

    /// 画面の本体
    var body: some View {
        Form {
            if let code = inviteCode, !code.isEmpty {

                Section(header: Text("招待コード")) {
                    HStack {
                        Text(code)
                            .font(.title2)
                            .monospaced()
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(header: Text("QRコード")) {
                    if let image = qrImage {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("QRコードを生成中…")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }

                Section(footer: Text("招待コード/QRを共有して、「招待コードで参加」画面から入力してもらってください。")) {
                    EmptyView()
                }

            } else {
                Section {
                    Text("この記録には招待コードがありません。新しく作成した記録でお試しください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("招待コード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .onAppear {
            updateQRCodeIfNeeded()
        }
    }

    /// QRコード画像を生成する
    private static func generateQRCode(from text: String) -> UIImage? {
        let data = Data(text.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    /// 招待コードに応じてQRコードを更新する
    private func updateQRCodeIfNeeded() {
        guard let code = inviteCode, !code.isEmpty else {
            qrImage = nil
            return
        }
        if qrImage == nil {
            qrImage = Self.generateQRCode(from: code)
        }
    }
}

#Preview {
    NavigationStack {
        GameRecordDetailPreviewHost()
    }
}

/// プレビュー用ホスト
private struct GameRecordDetailPreviewHost: View {
    /// ストレージViewModel
    @StateObject private var vm = StorageViewModel.shared

    /// 画面の本体
    var body: some View {
        GameRecordDetailView(
            record: PreviewData.previewDetailRecord,
            previewAdminUID: PreviewData.previewDetailRecord.createdBy
        )
            .task { @MainActor in
                vm.members = PreviewData.previewMembers
                vm.gameResults = PreviewData.previewGameResults
            }
    }
}
