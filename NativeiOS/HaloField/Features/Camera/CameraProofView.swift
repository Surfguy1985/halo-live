import SwiftUI
import PhotosUI

struct CameraProofView: View {
    let job: FieldJob
    let phase: String
    var task: JobTask?

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                HaloTheme.fieldBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(spacing: 7) {
                        Text(phase.uppercased())
                            .font(HaloType.body(11, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(HaloTheme.lime)
                        Text(task?.title ?? "Document the work")
                            .font(HaloType.card(25, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Unit \(job.unit) · \(job.propertyName)")
                            .font(HaloType.body(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(HaloTheme.fieldBorder) }

                        if let imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage).resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        } else {
                            VStack(spacing: 14) {
                                Image(systemName: "camera.fill").font(.system(size: 34, weight: .medium)).foregroundStyle(HaloTheme.lime)
                                Text("Capture required proof").font(HaloType.body(15, weight: .semibold)).foregroundStyle(.white)
                                Text("HALO attaches unit, task, phase, timestamp and verified location.")
                                    .font(HaloType.body(12)).foregroundStyle(.white.opacity(0.48))
                                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                            }
                        }
                    }.frame(maxHeight: .infinity)

                    if imageData == nil {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Take or Choose Photo", systemImage: "camera.fill")
                                .font(HaloType.body(15, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 58)
                                .background(HaloTheme.lime)
                                .foregroundStyle(Color(red: 13/255, green: 18/255, blue: 11/255))
                                .clipShape(Capsule())
                        }
                        .onChange(of: pickerItem) { _, newValue in
                            Task { imageData = try? await newValue?.loadTransferable(type: Data.self) }
                        }
                    } else {
                        VStack(spacing: 10) {
                            Button { dismiss() } label: {
                                Label("Use Photo", systemImage: "checkmark")
                                    .font(HaloType.body(15, weight: .bold))
                                    .frame(maxWidth: .infinity).frame(height: 58)
                                    .background(HaloTheme.lime)
                                    .foregroundStyle(Color(red: 13/255, green: 18/255, blue: 11/255))
                                    .clipShape(Capsule())
                            }
                            Button("Retake") { imageData = nil; pickerItem = nil }
                                .font(HaloType.body(13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62)).frame(height: 44)
                        }
                    }
                }.padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .frame(width: 36, height: 36).background(.white.opacity(0.08)).clipShape(Circle())
                    }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) { HaloLogo(height: 22) }
            }
            .toolbarBackground(HaloTheme.fieldBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}