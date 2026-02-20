//
//  ProfileViewModel.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Combine
import FirebaseAuth

/// プロフィール編集の状態と処理を管理するViewModel
@MainActor
final class ProfileViewModel: ObservableObject {
    /// 認証ViewModel
    private let auth: AuthViewModel

    /// 入力中の表示名
    @Published var newDisplayName: String = ""

    /// 選択中のPhotosPickerアイテム
    @Published var selectedItem: PhotosPickerItem? = nil
    /// 選択中の画像
    @Published var selectedImage: UIImage? = nil
    /// 表示中のプロフィール画像
    @Published var profileImage: UIImage? = nil
    /// プロフィール画像の読み込み中フラグ
    @Published var isProfileImageLoading: Bool = false
    /// 画像削除の予約フラグ
    @Published var isImageMarkedForDeletion: Bool = false

    /// 画像選択方法のシート表示フラグ
    @Published var showingSourceSheet: Bool = false
    /// 写真ライブラリのピッカー表示フラグ
    @Published var showingPhotosPicker: Bool = false
    /// ファイル選択の表示フラグ
    @Published var showingFileImporter: Bool = false

    /// 保存処理中フラグ
    @Published var isSaving: Bool = false

    /// アラート表示フラグ
    @Published var isShowingAlert: Bool = false
    /// アラートメッセージ
    @Published var alertMessage: String? = nil

    /// 共有認証ViewModelを使って初期化する
    init() {
        self.auth = .shared
    }

    /// 任意の認証ViewModelで初期化する
    init(auth: AuthViewModel) {
        self.auth = auth
    }

    /// 保存可能かどうかを判定する
    var canSave: Bool {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let nameChanged = !trimmed.isEmpty && trimmed != auth.displayName

        let imageChanged = (selectedImage != nil) || isImageMarkedForDeletion

        return (nameChanged || imageChanged) && !isSaving
    }

    /// 画面表示時の初期化を行う
    func onAppear() {
        newDisplayName = auth.displayName

        Task {
            await loadProfileImageIfNeeded()
        }
    }

    /// PhotosPickerの選択変更を処理する
    func handleSelectedItemChange(_ newItem: PhotosPickerItem?) {
        guard let item = newItem else { return }

        Task {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let uiImg = UIImage(data: data)
                else {
                    showError("画像の読み込みに失敗しました。")
                    return
                }
                selectedImage = uiImg
            } catch {
                showError("画像の読み込みに失敗しました。")
            }
        }
    }

    /// ファイル選択の結果を処理する
    func handleFileImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)

            guard let uiImg = UIImage(data: data) else {
                showError("画像ファイルではありません。PNG または JPEG を選択してください。")
                return
            }

            selectedImage = uiImg

        } catch {
            if (error as? CocoaError)?.code != .userCancelled {
                showError("ファイルの読み込みに失敗しました。")
            }
        }
    }

    /// 写真ライブラリを開く
    func chooseFromPhotos() {
        showingSourceSheet = false
        showingPhotosPicker = true
    }

    /// ファイル選択を開く
    func chooseFromFiles() {
        showingSourceSheet = false
        showingFileImporter = true
    }

    /// 画像削除を予約する
    func markImageForDeletion() {
        selectedImage = nil
        profileImage = nil
        isImageMarkedForDeletion = true
        showingSourceSheet = false
    }

    /// 既存のプロフィール画像を読み込む
    private func loadProfileImageIfNeeded() async {
        guard profileImage == nil,
              selectedImage == nil,
              !isImageMarkedForDeletion,
              let url = auth.user?.photoURL
        else { return }

        isProfileImageLoading = true
        defer { isProfileImageLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                profileImage = image
            }
        } catch {
            print("Failed to load profile image: \(error)")
        }
    }

    /// 表示名と画像の保存を行う
    func saveAll() {
        Task {
            isSaving = true
            defer { isSaving = false }

            let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != auth.displayName {
                do {
                    try await auth.updateDisplayName(to: trimmed)
                } catch {
                    showError(AuthErrorMapper.message(for: error))
                    return
                }
            }

            if let img = selectedImage {
                guard var data = img.jpegData(compressionQuality: 0.8) else {
                    showError("画像データの変換に失敗しました。")
                    return
                }

                let maxBytes = 5 * 1024 * 1024
                if data.count > maxBytes {
                    var compression: CGFloat = 0.7
                    while data.count > maxBytes && compression > 0.1 {
                        if let compressed = img.jpegData(compressionQuality: compression) {
                            data = compressed
                        }
                        compression -= 0.1
                    }
                }

                guard data.count <= maxBytes else {
                    showError("画像サイズが5MBを超えています。")
                    return
                }

                do {
                    try await auth.updateProfileImageData(data)

                    if let savedImage = UIImage(data: data) {
                        profileImage = savedImage
                    }

                    selectedImage = nil

                    isImageMarkedForDeletion = false

                } catch {
                    showError(AuthErrorMapper.message(for: error))
                    return
                }

            } else if isImageMarkedForDeletion {
                do {
                    try await auth.deleteProfileImage()
                    profileImage = nil
                    isImageMarkedForDeletion = false
                } catch {
                    showError(AuthErrorMapper.message(for: error))
                    return
                }
            }
        }
    }

    /// エラーを表示する
    private func showError(_ message: String) {
        alertMessage = message
        isShowingAlert = true
    }
}
