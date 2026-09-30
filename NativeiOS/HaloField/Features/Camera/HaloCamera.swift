@preconcurrency import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class HaloCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.archangel.halofield.camera")

    func start() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorization = AVCaptureDevice.authorizationStatus(for: .video)
                if granted { configureAndStart() }
                else { errorMessage = "Camera access is required to capture verified proof." }
            }
        default:
            errorMessage = "Camera access is disabled. Enable it in Settings to capture verified proof."
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() {
        guard isReady else { return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        output.capturePhoto(with: settings, delegate: self)
    }

    func retake() {
        capturedImage = nil
        errorMessage = nil
        if !session.isRunning { start() }
    }

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.session.inputs.isEmpty {
                if !self.session.isRunning { self.session.startRunning() }
                Task { @MainActor in self.isReady = true }
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            defer { self.session.commitConfiguration() }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.output)
            else {
                Task { @MainActor in
                    self.errorMessage = "HALO could not initialize this camera."
                    self.isReady = false
                }
                return
            }

            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.output.maxPhotoQualityPrioritization = .quality
            self.session.startRunning()

            Task { @MainActor in
                self.isReady = true
                self.errorMessage = nil
            }
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in self.errorMessage = "HALO could not process this photo." }
            return
        }
        Task { @MainActor in
            self.capturedImage = image
            self.stop()
        }
    }
}

struct HaloCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
