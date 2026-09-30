import SwiftData
import SwiftUI

struct JobDetailView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var session: HaloSessionStore
    @Environment(\.modelContext) private var modelContext
    let jobID: String

    @State private var showRoute = false
    @State private var showArrivalVerification = false
    @State private var proofPhase: String?
    @State private var proofTask: JobTask?

    private var job: FieldJob? { store.jobs.first(where: { $0.id == jobID }) }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        jobHeader(job)
                        progress(job)
                        taskList(job)
                        proof(job)
                        propertyNotes(job)
                    }
                    .padding(.horizontal, HaloTheme.horizontal)
                    .padding(.bottom, 112)
                }
                .background(
                    ZStack {
                        HaloTheme.fieldBackground
                        RadialGradient(colors: [HaloTheme.actionBlue.opacity(0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
                    }.ignoresSafeArea()
                )
                .safeAreaInset(edge: .bottom) { primaryAction(job) }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .sheet(isPresented: $showRoute) {
                    JobRouteView(job: job) {
                        if job.state == .scheduled {
                            store.setState(.enRoute, for: job.id)
                        }
                    }
                }
                .sheet(isPresented: $showArrivalVerification) {
                    ArrivalVerificationView(
                        job: job,
#if DEBUG
                        previewMode: store.isPreviewMode,
#endif
                        onVerified: { _ in
                            store.setState(.active, for: job.id)
                        }
                    )
                }
                .fullScreenCover(isPresented: Binding(
                    get: { proofPhase != nil },
                    set: { if !$0 { proofPhase = nil; proofTask = nil } }
                )) {
                    CameraProofView(job: job, phase: proofPhase ?? "Proof", task: proofTask)
                }
            } else {
                ContentUnavailableView("Job unavailable", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func jobHeader(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(job.kind.rawValue)
                    .font(HaloType.body(9, weight: .bold)).tracking(1.4)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(HaloTheme.lime).foregroundStyle(HaloTheme.ink).clipShape(Capsule())
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(job.state == .complete ? HaloTheme.success : HaloTheme.fieldLive).frame(width: 7, height: 7)
                    Text(job.state.rawValue.uppercased())
                        .font(HaloType.body(10, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.55))
                }
            }

            Text("Unit \(job.unit)")
                .font(HaloType.display(40, weight: .semibold))
                .tracking(-1.8)
                .foregroundStyle(.white)
            Text(job.title).font(HaloType.card(19, weight: .semibold)).foregroundStyle(.white.opacity(0.82))

            Button { showRoute = true } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(job.propertyName, systemImage: "building.2.fill")
                        Label(job.address, systemImage: "location.fill")
                    }
                    .font(HaloType.body(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(HaloTheme.lime)
                }
                .padding(16).haloDarkCard()
            }.buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func progress(_ job: FieldJob) -> some View {
        HStack(spacing: 15) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: job.progress)
                    .stroke(HaloTheme.lime, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(job.progress * 100))%")
                    .font(HaloType.body(10, weight: .bold))
                    .foregroundStyle(.white)
            }.frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(job.completedTasks) of \(job.tasks.count) tasks")
                    .font(HaloType.body(15, weight: .bold)).foregroundStyle(.white)
                Text(job.completedTasks == job.tasks.count ? "Ready for proof" : "HALO keeps the next required step obvious.")
                    .font(HaloType.body(12)).foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
        }
        .padding(18).haloDarkCard()
    }

    private func taskList(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCOPE").font(HaloType.body(10, weight: .bold)).tracking(1.7).foregroundStyle(.white.opacity(0.42))

            VStack(spacing: 0) {
                ForEach(job.tasks) { task in
                    HStack(alignment: .top, spacing: 14) {
                        Button {
                            store.toggleTask(jobID: job.id, taskID: task.id)
                            OfflineQueue.shared.enqueue(
                                jobID: job.id,
                                kind: .taskToggle,
                                payload: [
                                    "taskID": task.id,
                                    "isComplete": String(!task.isComplete)
                                ],
                                activationToken: session.activationToken,
                                context: modelContext
                            )
                        } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(task.isComplete ? HaloTheme.lime : .white.opacity(0.32))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(HaloType.body(14, weight: .semibold)).foregroundStyle(.white)
                            if let detail = task.detail {
                                Text(detail).font(HaloType.body(12)).foregroundStyle(.white.opacity(0.42))
                            }
                        }

                        Spacer()

                        if task.requiresPhoto {
                            Button {
                                proofPhase = task.isComplete ? "After" : "Before"
                                proofTask = task
                            } label: {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.07))
                                    .foregroundStyle(HaloTheme.lime)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    if task.id != job.tasks.last?.id {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
            .padding(.horizontal, 16)
            .haloDarkCard()
        }
    }

    private func proof(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PROOF").font(HaloType.body(10, weight: .bold)).tracking(1.7).foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text("\(job.photoCount) PHOTOS").font(HaloType.body(9, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.35))
            }

            HStack(spacing: 12) {
                proofTile(job: job, title: "Before", count: max(job.photoCount - 3, 0), done: job.photoCount >= 5)
                proofTile(job: job, title: "After", count: min(job.photoCount, 3), done: false)
            }
        }
    }

    private func proofTile(job: FieldJob, title: String, count: Int, done: Bool) -> some View {
        Button {
            proofPhase = title
            proofTask = nil
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: done ? "checkmark.seal.fill" : "camera.fill")
                    .font(.title2).foregroundStyle(done ? HaloTheme.lime : .white)
                Text(title).font(HaloType.card(15, weight: .semibold)).foregroundStyle(.white)
                Text("\(count) captured").font(HaloType.body(10)).foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).haloDarkCard()
        }.buttonStyle(.plain)
    }

    private func propertyNotes(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROPERTY NOTES").font(HaloType.body(10, weight: .bold)).tracking(1.7).foregroundStyle(.white.opacity(0.42))
            Label("Gate 3142 · Keybox 8821", systemImage: "key.fill")
            Label("Flag additional work from any task", systemImage: "flag.fill")
        }
        .font(HaloType.body(12, weight: .medium))
        .foregroundStyle(.white.opacity(0.62))
        .padding(18).haloDarkCard()
    }

    private func primaryAction(_ job: FieldJob) -> some View {
        Button {
            if job.state == .scheduled {
                showRoute = true
            } else if job.state == .enRoute || job.state == .arrived {
                showArrivalVerification = true
            } else {
                let from = job.state.rawValue
                store.advance(job.id)
                let to = store.jobs.first(where: { $0.id == job.id })?.state.rawValue ?? from
                OfflineQueue.shared.enqueue(
                    jobID: job.id,
                    kind: .workflowState,
                    payload: ["from": from, "to": to],
                    activationToken: session.activationToken,
                    context: modelContext
                )
            }
        } label: {
            HStack {
                Text(job.state.actionTitle)
                Spacer()
                Image(systemName: job.state == .scheduled ? "location.fill" : "arrow.right")
            }
            .font(HaloType.body(15, weight: .bold))
            .padding(.horizontal, 22)
            .frame(height: 58)
            .background(job.state == .complete ? Color.white.opacity(0.08) : HaloTheme.lime)
            .foregroundStyle(job.state == .complete ? .white.opacity(0.35) : HaloTheme.ink)
            .clipShape(Capsule())
        }
        .disabled(job.state == .complete)
        .padding(.horizontal, HaloTheme.horizontal)
        .padding(.top, 10).padding(.bottom, 8)
        .background(.ultraThinMaterial.opacity(0.94))
    }
}
