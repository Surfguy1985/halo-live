import SwiftUI

struct JobDetailView: View {
    @EnvironmentObject private var store: JobStore
    let jobID: UUID

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
                .background(HaloTheme.paper.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    primaryAction(job)
                }
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Job unavailable", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func jobHeader(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(job.kind.rawValue)
                    .font(.caption2.weight(.black)).tracking(1.2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(HaloTheme.ink).foregroundStyle(.white).clipShape(Capsule())
                Spacer()
                Text(job.state.rawValue.uppercased())
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Text("Unit \(job.unit)")
                .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1)
            Text(job.title).font(.title3.weight(.semibold))
            Label(job.propertyName, systemImage: "building.2.fill")
                .font(.subheadline).foregroundStyle(.secondary)
            Label(job.address, systemImage: "location.fill")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func progress(_ job: FieldJob) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(HaloTheme.hairline, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: job.progress)
                    .stroke(HaloTheme.lime, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(job.progress * 100))%").font(.caption.weight(.bold))
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(job.completedTasks) of \(job.tasks.count) tasks")
                    .font(.headline)
                Text(job.completedTasks == job.tasks.count ? "Ready for proof" : "Keep moving — HALO tracks the rest.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18).haloCard()
    }

    private func taskList(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scope").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                ForEach(job.tasks) { task in
                    Button {
                        store.toggleTask(jobID: job.id, taskID: task.id)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(task.isComplete ? HaloTheme.ink : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.body.weight(.semibold)).foregroundStyle(HaloTheme.ink)
                                if let detail = task.detail {
                                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if task.requiresPhoto {
                                Image(systemName: "camera.fill").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    if task.id != job.tasks.last?.id { Divider().opacity(0.6) }
                }
            }
            .padding(.horizontal, 16).haloCard()
        }
    }

    private func proof(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Proof").font(.title3.weight(.semibold))
                Spacer()
                Text("\(job.photoCount) photos").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                proofTile(title: "Before", count: max(job.photoCount - 3, 0), done: job.photoCount >= 5)
                proofTile(title: "After", count: min(job.photoCount, 3), done: false)
            }
        }
    }

    private func proofTile(title: String, count: Int, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: done ? "checkmark.seal.fill" : "camera.fill")
                .font(.title2).foregroundStyle(done ? HaloTheme.lime : HaloTheme.ink)
            Text(title).font(.headline)
            Text("\(count) captured").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).haloCard()
    }

    private func propertyNotes(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Property notes").font(.title3.weight(.semibold))
            Label("Gate 3142 · Keybox 8821", systemImage: "key.fill")
                .font(.subheadline)
            Label("Flag additional work from any task", systemImage: "flag.fill")
                .font(.subheadline)
        }
        .padding(18).haloCard()
    }

    private func primaryAction(_ job: FieldJob) -> some View {
        Button {
            store.advance(job.id)
        } label: {
            HStack {
                Text(job.state.actionTitle)
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(job.state == .complete ? Color.gray.opacity(0.2) : HaloTheme.ink)
            .foregroundStyle(job.state == .complete ? .secondary : .white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .disabled(job.state == .complete)
        .padding(.horizontal, HaloTheme.horizontal)
        .padding(.top, 10).padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}
