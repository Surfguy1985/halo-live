@preconcurrency import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class HaloCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    static var isSimulator: Bool {
#if targetEnvironment(simulator)
        true
#else
        false
#endif
    }
    @Published private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.archangel.halofield.camera")
    private let cameraPosition: AVCaptureDevice.Position

    init(position: AVCaptureDevice.Position = .back) {
        self.cameraPosition = position
        super.init()
    }

    func start() {
#if targetEnvironment(simulator)
        authorization = .authorized
        errorMessage = nil
        isReady = true
        return
#endif
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
#if targetEnvironment(simulator)
        isReady = false
        return
#endif
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() {
        guard isReady else { return }
#if targetEnvironment(simulator)
        capturedImage = simulatorImage()
        isReady = false
        return
#endif
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        output.capturePhoto(with: settings, delegate: self)
    }

    func retake() {
        capturedImage = nil
        errorMessage = nil
#if targetEnvironment(simulator)
        isReady = true
#else
        if !session.isRunning { start() }
#endif
    }

#if targetEnvironment(simulator)
    private func simulatorImage() -> UIImage {
        let size = CGSize(width: 1170, height: 1560)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 7/255, green: 16/255, blue: 29/255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let lime = UIColor(red: 185/255, green: 255/255, blue: 102/255, alpha: 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let title = NSAttributedString(
                string: "HALO",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 112, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            )
            title.draw(in: CGRect(x: 80, y: 480, width: size.width - 160, height: 150))

            let subtitle = NSAttributedString(
                string: "SIMULATOR CAMERA\n\(cameraPosition == .front ? "FRONT VERIFICATION" : "FIELD PROOF")",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 38, weight: .semibold),
                    .foregroundColor: lime,
                    .paragraphStyle: paragraph
                ]
            )
            subtitle.draw(in: CGRect(x: 80, y: 650, width: size.width - 160, height: 140))

            let stamp = NSAttributedString(
                string: Date().formatted(date: .abbreviated, time: .standard),
                attributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.58),
                    .paragraphStyle: paragraph
                ]
            )
            stamp.draw(in: CGRect(x: 80, y: 850, width: size.width - 160, height: 80))
        }
    }
#endif

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
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
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
