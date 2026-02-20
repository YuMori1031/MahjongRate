//
//  AuthViewModel.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import Foundation
import Combine
import UIKit

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

/// 認証状態とアカウント操作を管理するViewModel
@MainActor
final class AuthViewModel: ObservableObject {
    /// 共有インスタンス
    static let shared = AuthViewModel()

    /// 現在のログインユーザー
    @Published var user: User? = nil
    /// 認証状態の初期化完了フラグ
    @Published var isAuthInitialized: Bool = false

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {}

    /// 認証状態の監視を開始する
    func start() {
        guard handle == nil, FirebaseApp.app() != nil else { return }

        isAuthInitialized = false

        if let current = Auth.auth().currentUser {
            self.user = current
        } else {
            self.user = nil
        }

        isAuthInitialized = true

        if let current = Auth.auth().currentUser {
            Task { @MainActor in
                do {
                    try await reloadUser(current)

                    if current.isEmailVerified {
                        self.user = current
                        runPostLoginSetup(for: current)
                    } else {
                        try? Auth.auth().signOut()
                        self.user = nil
                    }
                } catch {
                    try? Auth.auth().signOut()
                    self.user = nil
                }
            }
        }

        handle = Auth.auth().addStateDidChangeListener { [weak self] _, newUser in
            guard let self else { return }

            guard let u = newUser else {
                self.user = nil
                return
            }

            Task { @MainActor in
                do {
                    try await self.reloadUser(u)

                    if u.isEmailVerified {
                        self.user = u
                        self.runPostLoginSetup(for: u)
                    } else {
                        try? Auth.auth().signOut()
                        self.user = nil
                    }
                } catch {
                    try? Auth.auth().signOut()
                    self.user = nil
                }
            }
        }
    }

    /// 認証状態の監視を停止する
    func stopListening() {
        if let h = handle {
            Auth.auth().removeStateDidChangeListener(h)
            handle = nil
        }
    }

    deinit {
        if let h = handle {
            Auth.auth().removeStateDidChangeListener(h)
        }
    }

    /// 表示用のユーザー名
    var displayName: String {
        user?.displayName ?? "ゲスト"
    }

    /// 新規登録と認証メール送信を行う
    func signUp(email: String, password: String, username: String) async throws {
        stopListening()
        defer { start() }

        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let newUser = result.user

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let req = newUser.createProfileChangeRequest()
            req.displayName = username
            req.commitChanges { error in
                if let e = error { cont.resume(throwing: e) }
                else { cont.resume(returning: ()) }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            newUser.sendEmailVerification { error in
                if let e = error { cont.resume(throwing: e) }
                else { cont.resume(returning: ()) }
            }
        }

        try Auth.auth().signOut()
        user = nil
    }

    /// ログイン処理を行う
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        let loggedIn = result.user

        try await reloadUser(loggedIn)
        if !loggedIn.isEmailVerified {
            try Auth.auth().signOut()
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "メール認証が完了していません。メール内のリンクをクリックしてください。"
                ]
            )
        }

        self.user = loggedIn
        runPostLoginSetup(for: loggedIn)
    }

    /// ログアウトする
    func signOut() throws {
        StorageViewModel.shared.reset()
        try Auth.auth().signOut()
        user = nil
    }

    /// 再認証を行う
    private func reauthenticate(password: String) async throws {
        guard let email = Auth.auth().currentUser?.email else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "メールアドレスが取得できませんでした。"]
            )
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        _ = try await Auth.auth().currentUser!.reauthenticate(with: credential)
    }

    /// アカウントを削除する
    func deleteAccount(password: String) async throws {
        try await reauthenticate(password: password)

        let functions = Functions.functions(region: "asia-northeast2")
        let callable = functions.httpsCallable("deleteMyAccount")

        _ = try await callable.call(["confirm": "DELETE"])

        StorageViewModel.shared.reset()

        try? Auth.auth().signOut()

        self.user = nil
    }

    /// メールアドレス変更の確認メールを送信する
    func requestEmailUpdate(to newEmail: String, currentPassword: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ログイン中のユーザーが見つかりません。再ログインしてください。"
                ]
            )
        }

        let oldEmail = currentUser.email ?? ""
        let credential = EmailAuthProvider.credential(
            withEmail: oldEmail,
            password: currentPassword
        )
        try await currentUser.reauthenticate(with: credential)

        try await currentUser.sendEmailVerification(beforeUpdatingEmail: newEmail)
    }

    /// 現在ユーザーを再読み込みする
    func reloadUser() async throws {
        try await Auth.auth().currentUser?.reload()
        self.user = Auth.auth().currentUser
    }

    /// パスワードを変更する
    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let currentUser = Auth.auth().currentUser,
              let email = currentUser.email
        else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ログイン中のユーザー情報が取得できません。再ログインしてください。"
                ]
            )
        }

        let credential = EmailAuthProvider.credential(
            withEmail: email,
            password: currentPassword
        )

        try await currentUser.reauthenticate(with: credential)

        try await currentUser.updatePassword(to: newPassword)
    }

    /// パスワード再設定メールを送信する
    func sendPasswordResetEmail(to email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    /// 表示名を更新する
    func updateDisplayName(to newName: String) async throws {
        guard let current = Auth.auth().currentUser else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ユーザーが取得できませんでした。再ログインしてください。"
                ]
            )
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let req = current.createProfileChangeRequest()
            req.displayName = newName
            req.commitChanges { error in
                if let e = error {
                    cont.resume(throwing: e)
                } else {
                    self.user = Auth.auth().currentUser
                    cont.resume(returning: ())
                }
            }
        }
    }

    /// プロフィール画像をデータで更新する
    func updateProfileImageData(_ data: Data) async throws {
        guard let current = Auth.auth().currentUser else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ユーザーが取得できませんでした。再ログインしてください。"]
            )
        }

        let objectPath = "profileImages/\(current.uid).jpg"

        let ref = Storage.storage().reference().child(objectPath)

        _ = try await ref.putDataAsync(data, metadata: nil)

        let url = try await ref.downloadURL()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let req = current.createProfileChangeRequest()
            req.photoURL = url
            req.commitChanges { err in
                if let e = err { cont.resume(throwing: e) }
                else { cont.resume(returning: ()) }
            }
        }

        self.user = Auth.auth().currentUser

        do {
            try await FirestoreStorage().updateMyMemberIcon(
                iconURL: url.absoluteString,
                iconPath: objectPath
            )
        } catch {
            print("❌ updateMyMemberIcon error:", error)
        }
    }

    /// プロフィール画像を更新する
    func updateProfileImage(_ image: UIImage) async throws {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "画像データの変換に失敗しました。"
                ]
            )
        }
        try await updateProfileImageData(data)
    }

    /// プロフィール画像を削除する
    func deleteProfileImage() async throws {
        guard let current = Auth.auth().currentUser else {
            throw NSError(
                domain: "AuthViewModel",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ユーザーが取得できませんでした。再ログインしてください。"]
            )
        }

        let ref = Storage.storage()
            .reference()
            .child("profileImages/\(current.uid).jpg")

        do {
            try await ref.delete()
        } catch {
            let nsErr = error as NSError
            if nsErr.domain == StorageErrorDomain,
               let code = StorageErrorCode(rawValue: nsErr.code),
               code == .objectNotFound {
            } else {
                throw error
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let req = current.createProfileChangeRequest()
            req.photoURL = nil
            req.commitChanges { err in
                if let e = err { cont.resume(throwing: e) }
                else { cont.resume(returning: ()) }
            }
        }

        self.user = Auth.auth().currentUser

        do {
            try await FirestoreStorage().updateMyMemberIcon(iconURL: nil, iconPath: nil)
        } catch {
            print("❌ updateMyMemberIcon(nil,nil) error:", error)
        }
    }

    /// ログイン後の初期化処理を実行する
    private func runPostLoginSetup(for user: User) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.reloadUser(user)

                guard user.isEmailVerified else { return }

                _ = try await self.getIDToken(user)

                try await self.ensureMemberWithRetry()

                if StorageViewModel.shared.members.isEmpty {
                    StorageViewModel.shared.startMembers()
                }
            } catch {
                print("❌ runPostLoginSetup error:", error)
            }
        }
    }

    /// ユーザー情報を再読み込みする
    private func reloadUser(_ user: User) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            user.reload { error in
                if let e = error { cont.resume(throwing: e) }
                else { cont.resume(returning: ()) }
            }
        }
    }

    /// IDトークンを取得する
    private func getIDToken(_ user: User) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let e = error { cont.resume(throwing: e) }
                else { cont.resume(returning: token ?? "") }
            }
        }
    }

    /// メンバー情報の作成をリトライ付きで実行する
    private func ensureMemberWithRetry() async throws {
        let storage = FirestoreStorage()
        var lastError: Error?

        for attempt in 1...5 {
            do {
                try await storage.ensureCurrentUserMemberExists()
                return
            } catch {
                lastError = error
                let delay = UInt64(250_000_000 * attempt)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        if let lastError { throw lastError }
    }
}
