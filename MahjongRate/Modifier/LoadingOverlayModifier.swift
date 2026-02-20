//
//  LoadingOverlayModifier.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/03.
//

import SwiftUI

/// ローディングオーバーレイを表示するViewModifier
struct LoadingOverlayModifier: ViewModifier {
    /// 表示フラグ
    let isPresented: Bool
    /// 表示メッセージ
    let message: String

    /// オーバーレイを合成する
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isPresented)

            if isPresented {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.3)

                    Text(message)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding(32)
                .background(.regularMaterial)
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
    }
}

extension View {
    /// ローディングオーバーレイを付与する
    func loadingOverlay(isPresented: Bool, message: String) -> some View {
        self.modifier(LoadingOverlayModifier(isPresented: isPresented, message: message))
    }
}
