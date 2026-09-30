import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CameraProofView: View {
    let job: FieldJob
    let phase: String
    var task: JobTask?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var session: HaloSessionStore
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera = HaloCameraController()
    @State private var pickerItem: PhotosPickerItem?
    @State private var importedImage: UIImage?
    @State private var source = "camera"
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedProof: StoredProof?

    private var image: UIImage? { camera.capturedImage ?? importedImage }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    review(image)
                } else {
                    liveCamera
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.46))
                            .clipShape(Circle())
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) { HaloLogo(height: 22) }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                location.requestPermission()
                location.refresh()
                camera.start()
            }
            .onDisappear { camera.stop() }
        }
    }

    private var liveCamera: some View {
        ZStack {
            HaloCameraPreview(session: camera.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                captureHeader
                    .padding(.top, 54)
                Spacer()
                proofGuide
                Spacer()
                captureControls
            }
            .padding(.horizontal, 20)

            if let error = camera.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(HaloTheme.lime)
                    Text(error)
                        .font(HaloType.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    if camera.authorization == .denied || camera.authorization == .restricted {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Camera Settings", systemImage: "gearshape.fill")
                                .font(HaloType.body(11, weight: .bold))
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(HaloTheme.lime)
                    }
                }
                .padding(22)
                .background(.black.opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(30)
            }
        }
    }

    private var captureHeader: some View {
        VStack(spacing: 7) {
            Text(phase.uppercased())
                .font(HaloType.body(10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(HaloTheme.lime)
            Text(task?.title ?? "Document the work")
                .font(HaloType.card(22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Unit \(job.unit) · \(job.propertyName)")
                .font(HaloType.body(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var proofGuide: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [9, 7]))
            .frame(height: 330)
            .overlay(alignment: .topLeading) {
                Text("FRAME THE FULL WORK AREA")
                    .font(HaloType.body(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(14)
            }
            .allowsHitTesting(false)
    }

    private var captureControls: some View {
        VStack(spacing: 14) {
            HStack {
                locationBadge
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(.black.opacity(0.48))
                        .clipShape(Circle())
                }
                .foregroundStyle(.white)
                .onChange(of: pickerItem) { _, newValue in
                    Task {
                        guard
                            let data = try? await newValue?.loadTransferable(type: Data.self),
                            let photo = UIImage(data: data)
                        else { return }
                        source = "library"
                        importedImage = photo
                        camera.stop()
                    }
                }
            }

            Button {
                source = "camera"
                camera.capture()
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 78, height: 78)
                    Circle().stroke(.black.opacity(0.28), lineWidth: 3).frame(width: 66, height: 66)
                }
            }
            .disabled(!camera.isReady)
            .opacity(camera.isReady ? 1 : 0.5)
            .accessibilityLabel("Capture proof photo")

            Text("HALO PROOF · JOB \(job.jobNo ?? job.id.prefix(8).uppercased())")
                .font(HaloType.body(9, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.48))
                .padding(.bottom, 18)
        }
    }

    private var locationBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(location.location == nil ? Color.orange : HaloTheme.fieldLive)
                .frame(width: 7, height: 7)
            Text(location.location.map { "GPS ±\(Int(max($0.horizontalAccuracy, 0)))m" } ?? "Acquiring GPS")
                .font(HaloType.body(10, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(.black.opacity(0.48))
        .clipShape(Capsule())
    }

    private func review(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                captureHeader.padding(.top, 54)
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        metadataChip(icon: "clock.fill", text: Date().formatted(date: .omitted, time: .shortened))
                        metadataChip(icon: "location.fill", text: location.location == nil ? "GPS pending" : "GPS verified")
                        metadataChip(icon: "camera.fill", text: phase)
                    }

                    if let saveError {
                        Text(saveError)
                            .font(HaloType.body(11, weight: .semibold))
                            .foregroundStyle(.red)
                    }

                    if savedProof != nil {
                        Label("Saved securely on this iPhone", systemImage: "checkmark.seal.fill")
                            .font(HaloType.body(12, weight: .bold))
                            .foregroundStyle(HaloTheme.lime)
                    }

                    Button {
                        save(image)
                    } label: {
                        HStack {
                            Text(isSaving ? "Saving Proof…" : "Use This Proof")
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                        .font(HaloType.body(15, weight: .bold))
                        .padding(.horizontal, 22)
                        .frame(height: 58)
                        .background(HaloTheme.lime)
                        .foregroundStyle(HaloTheme.ink)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving)

                    Button("Retake") {
                        savedProof = nil
                        saveError = nil
                        importedImage = nil
                        pickerItem = nil
                        camera.retake()
                    }
                    .font(HaloType.body(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(20)
                .background(.black.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(20)
            }
        }
    }

    private func metadataChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(9, weight: .bold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.white.opacity(0.10))
            .clipShape(Capsule())
    }

    private func save(_ image: UIImage) {
        isSaving = true
        saveError = nil

        Task {
            do {
                let proof = try await ProofStorage.shared.save(
                    image: image,
                    job: job,
                    task: task,
                    phase: phase,
                    location: location.location,
                    source: source
                )
                await MainActor.run {
                    savedProof = proof
                    store.recordLocalProof(jobID: job.id, phase: proof.metadata.phase)
                    OfflineQueue.shared.enqueue(
                        jobID: job.id,
                        kind: .proofCaptured,
                        payload: [
                            "proofID": proof.metadata.proofID,
                            "phase": proof.metadata.phase,
                            "imagePath": proof.imageURL.path,
                            "metadataPath": proof.metadataURL.path
                        ],
                        activationToken: session.activationToken,
                        context: modelContext
                    )
                    isSaving = false
                }
                try? await Task.sleep(for: .milliseconds(450))
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    saveError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
