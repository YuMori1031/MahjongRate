//
//  ProfileView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// プロフィール編集画面
struct ProfileView: View {
    /// プロフィール編集の状態を保持するViewModel
    @StateObject private var vm: ProfileViewModel

    /// 既定のViewModelで初期化する
    init() {
        _vm = StateObject(wrappedValue: ProfileViewModel())
    }

    /// テスト用のViewModelで初期化する
    init(viewModel: ProfileViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    /// プロフィール編集画面
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("プロフィール画像")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Divider()

                HStack {
                    Spacer()
                    avatarView
                        .onTapGesture {
                            vm.showingSourceSheet = true
                        }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ユーザー名")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Divider()

                ZStack(alignment: .trailing) {
                    TextField("ユーザー名", text: $vm.newDisplayName)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.none)

                    if !vm.newDisplayName.isEmpty {
                        Button {
                            vm.newDisplayName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    vm.saveAll()
                } label: {
                    Text("保存")
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(vm.canSave ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(24)
                        .shadow(radius: vm.canSave ? 3 : 0)
                }
                .disabled(!vm.canSave)
                Spacer()
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        .navigationTitle("プロフィール")
        .navigationBarTitleDisplayMode(.inline)

        .onAppear {
            vm.onAppear()
        }

        .onChange(of: vm.selectedItem) { _, newItem in
            vm.handleSelectedItemChange(newItem)
        }

        .sheet(isPresented: $vm.showingSourceSheet) {
            VStack(spacing: 20) {
                Text("画像の選択方法")
                    .font(.headline)
                    .padding(.top, 12)

                Button {
                    vm.chooseFromPhotos()
                } label: {
                    Label("写真ライブラリから選択", systemImage: "photo")
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    vm.chooseFromFiles()
                } label: {
                    Label("ファイルから選択", systemImage: "folder")
                        .font(.title3)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    vm.markImageForDeletion()
                } label: {
                    Label("画像を削除", systemImage: "trash")
                        .font(.title3)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Divider().padding(.horizontal)

                Button("キャンセル") {
                    vm.showingSourceSheet = false
                }
                .font(.title3)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
        }

        .photosPicker(
            isPresented: $vm.showingPhotosPicker,
            selection: $vm.selectedItem,
            matching: .images
        )

        .fileImporter(
            isPresented: $vm.showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            vm.handleFileImportResult(result)
        }

        .alert("エラー", isPresented: $vm.isShowingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.alertMessage ?? "エラーが発生しました。")
        }

        .loadingOverlay(isPresented: vm.isSaving, message: "保存中…")
    }

    /// プロフィール画像の表示
    private var avatarView: some View {
        Group {
            if let uiImage = vm.selectedImage ?? vm.profileImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if vm.isProfileImageLoading {
                ProgressView()
                    .scaleEffect(1.4)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
