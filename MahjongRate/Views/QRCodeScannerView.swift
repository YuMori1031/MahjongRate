//
//  QRCodeScannerView.swift
//  MahjongRate
//
//  Created by Yusuke Mori on 2026/02/04.
//

import SwiftUI
import AVFoundation

/// QRコード読み取りのラッパービュー
struct QRCodeScannerView: UIViewControllerRepresentable {
    /// 読み取り成功時のハンドラ
    let onScan: (String) -> Void
    /// キャンセル時のハンドラ
    var onCancel: (() -> Void)? = nil

    /// UIKit 側のデリゲートを用意する
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// スキャナーのUIViewControllerを生成する
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    /// 更新処理の受け皿
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
    }

    /// スキャナーイベントを受け取るCoordinator
    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        /// 親ビューへの参照
        let parent: QRCodeScannerView

        /// Coordinatorを初期化する
        init(parent: QRCodeScannerView) {
            self.parent = parent
        }

        /// QRコード読み取り時の通知
        func scannerViewController(_ controller: ScannerViewController, didScanCode code: String) {
            parent.onScan(code)
        }

        /// キャンセル時の通知
        func scannerViewControllerDidCancel(_ controller: ScannerViewController) {
            parent.onCancel?()
        }
    }
}

/// スキャナーの通知を受け取るプロトコル
protocol ScannerViewControllerDelegate: AnyObject {
    func scannerViewController(_ controller: ScannerViewController, didScanCode code: String)
    func scannerViewControllerDidCancel(_ controller: ScannerViewController)
}

/// QRコードの読み取りを行うViewController
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    /// スキャナーの通知先
    weak var delegate: ScannerViewControllerDelegate?

    /// キャプチャセッション
    private let session = AVCaptureSession()
    /// プレビュー表示レイヤー
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// セッション操作用のキュー
    private let sessionQueue = DispatchQueue(label: "qr.scanner.session.queue")
    /// 停止処理中かどうか
    private var isStopping = false

    /// 画面の初期設定を行う
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }

    /// プレビューの表示位置を更新する
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    /// 表示タイミングでセッションを開始する
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// 画面を離れるときにセッションを停止する
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSessionIfNeeded()
    }

    /// キャンセル操作を通知する
    @objc private func cancelTapped() {
        delegate?.scannerViewControllerDidCancel(self)
        stopSessionIfNeeded()
    }

    /// セッションを必要に応じて停止する
    private func stopSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isStopping else { return }
            self.isStopping = true

            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// カメラ入力とQRコード出力を設定する
    private func setupCamera() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            print("❌ カメラデバイスが取得できませんでした")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)

                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let preview = AVCaptureVideoPreviewLayer(session: self.session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = self.view.bounds
                self.view.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
            }
        } catch {
            print("❌ カメラのセットアップに失敗しました:", error)
        }
    }

    /// QRコードの読み取り結果を受け取る
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {

        guard let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              first.type == .qr,
              let stringValue = first.stringValue else {
            return
        }

        stopSessionIfNeeded()

        delegate?.scannerViewController(self, didScanCode: stringValue)
    }
}

#Preview {
    NavigationStack {
        QRCodeScannerView(
            onScan: { code in
                print("Scanned:", code)
            },
            onCancel: {
                print("Cancelled")
            }
        )
        .navigationTitle("QRコードを読み取る")
        .navigationBarTitleDisplayMode(.inline)
    }
}
