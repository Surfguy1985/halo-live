import SwiftData
import SwiftUI

struct JobDetailView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var liveActivity: HaloLiveActivityController
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var modelContext
    let jobID: String

    @State private var showRoute = false
    @State private var showArrivalVerification = false
    @State private var showAdditionalWork = false
    @State private var showMessages = false
    @State private var proofPhase: String?
    @State private var proofTask: JobTask?
    @State private var reworkBusy = Set<Int>()
    @State private var reworkError: String?

    private var job: FieldJob? { store.jobs.first(where: { $0.id == jobID }) }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        jobHeader(job)
                        if job.state == .scheduled || job.state == .enRoute || job.state == .arrived {
                            photoCheckInCard(job)
                        }
                        fullScope(job)
                        WorkSessionCard(job: job)
                        if job.needsRework == true || job.unresolvedReworkCount > 0 {
                            reworkPanel(job)
                        }
                        progress(job)
                        taskList(job)
                        proof(job)
                        if job.kind == .maintenance && !job.isClosed {
                            additionalWork(job)
                        }
                        if job.readyForWalk == true || job.walkVerified == true || (job.closeoutStage ?? "active") != "active" {
                            closeoutStatus(job)
                        }
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
                    JobRouteView(
                        job: job,
                        onStartRoute: {
                            if job.state == .scheduled {
                                store.setState(.enRoute, for: job.id)
                            }
                        },
                        onVerifyArrival: {
                            if job.state == .scheduled {
                                store.setState(.enRoute, for: job.id)
                            }
                            showArrivalVerification = true
                        }
                    )
                }
                .sheet(isPresented: $showArrivalVerification) {
                    ArrivalVerificationView(
                        job: job,
                        previewMode: debugPreviewMode,
                        onVerified: { _ in
                            store.setState(.active, for: job.id)
                        }
                    )
                }
                .sheet(isPresented: $showAdditionalWork) {
                    AdditionalWorkView(job: job)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showMessages) {
                    NavigationStack {
                        HaloCommsView(initialJobID: job.id)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { proofPhase != nil },
                    set: { if !$0 { proofPhase = nil; proofTask = nil } }
                )) {
                    CameraProofView(job: job, phase: proofPhase ?? "Proof", task: proofTask)
                }
                .task {
                    liveActivity.restoreState()
                    if shouldShowLiveActivity(for: job) {
                        await liveActivity.startOrUpdate(job: job)
                    }
                }
                .onChange(of: job) { _, updated in
                    Task {
                        if updated.state == .complete {
                            await liveActivity.end(job: updated)
                        } else if shouldShowLiveActivity(for: updated) {
                            await liveActivity.startOrUpdate(job: updated)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Job unavailable", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func shouldShowLiveActivity(for job: FieldJob) -> Bool {
        switch job.state {
        case .enRoute, .arrived, .active, .proof, .review:
            true
        case .scheduled, .complete, .hold:
            false
        }
    }

    private var debugPreviewMode: Bool {
#if DEBUG
        store.isPreviewMode
#else
        false
#endif
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

    private func photoCheckInCard(_ job: FieldJob) -> some View {
        Button {
            showArrivalVerification = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(HaloTheme.lime)
                        .frame(width: 56, height: 56)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(HaloTheme.ink)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check in")
                        .font(HaloType.body(16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Take a photo to verify you’re on site.")
                        .font(HaloType.body(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [HaloTheme.lime.opacity(0.10), Color.white.opacity(0.035)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(HaloTheme.lime.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func fullScope(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FULL SCOPE")
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(HaloTheme.lime)

                Spacer()

                Text("\(job.scopeItemCount) ITEM\(job.scopeItemCount == 1 ? "" : "S")")
                    .font(HaloType.body(9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(0.36))
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    scopeMetric(
                        icon: "bed.double.fill",
                        title: "UNIT",
                        value: job.bedrooms.map { "\($0) BR" } ?? "Unit \(job.unit)"
                    )
                    scopeMetric(
                        icon: "flag.fill",
                        title: "PRIORITY",
                        value: (job.priority ?? "green").uppercased()
                    )
                    scopeMetric(
                        icon: "camera.fill",
                        title: "PROOF",
                        value: "\(job.beforePhotoCount)B · \(job.afterPhotoCount)A"
                    )
                }

                if !job.services.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("ASSIGNED SERVICES")
                            .font(HaloType.body(9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.36))

                        ForEach(Array(job.services.enumerated()), id: \.offset) { index, service in
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(HaloTheme.lime.opacity(0.12))
                                        .frame(width: 24, height: 24)
                                    Text("\(index + 1)")
                                        .font(HaloType.body(9, weight: .bold))
                                        .foregroundStyle(HaloTheme.lime)
                                }
                                Text(service)
                                    .font(HaloType.body(13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                        }
                    }
                }

                if let notes = job.scopeNotes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCOPE NOTES")
                            .font(HaloType.body(9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.36))
                        Text(notes)
                            .font(HaloType.body(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .foregroundStyle(HaloTheme.actionBlue)
                    Text("\(job.tasks.count) checklist item\(job.tasks.count == 1 ? "" : "s") loaded from Back Office")
                        .font(HaloType.body(10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.46))
                }
            }
            .padding(16)
            .haloDarkCard()
        }
    }

    private func scopeMetric(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(HaloTheme.lime)
            Text(title)
                .font(HaloType.body(8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.34))
            Text(value)
                .font(HaloType.body(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldJourney(_ job: FieldJob) -> some View {
        let workDone = !job.tasks.isEmpty && job.completedTasks == job.tasks.count
        let steps: [(String, String, Bool, Bool)] = [
            ("Before", "camera.fill", job.beforePhotoCount > 0, job.beforePhotoCount == 0),
            ("Work", "wrench.and.screwdriver.fill", workDone, job.beforePhotoCount > 0 && !workDone),
            ("After", "camera.fill", job.afterPhotoCount > 0, workDone && job.afterPhotoCount == 0),
            ("Submit", "checkmark.seal.fill", job.state == .review || job.state == .complete, job.afterPhotoCount > 0 && job.state != .review && job.state != .complete)
        ]

        return VStack(alignment: .leading, spacing: 11) {
            Text("JOB FLOW")
                .font(HaloType.body(10, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(.white.opacity(0.42))

            HStack(spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(step.2 ? HaloTheme.lime : (step.3 ? HaloTheme.actionBlue : Color.white.opacity(0.06)))
                                .frame(width: 34, height: 34)
                            Image(systemName: step.2 ? "checkmark" : step.1)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(step.2 ? HaloTheme.ink : .white)
                        }

                        Text(step.0)
                            .font(HaloType.body(9, weight: .bold))
                            .foregroundStyle(step.2 ? HaloTheme.lime : (step.3 ? .white : .white.opacity(0.36)))
                    }
                    .frame(maxWidth: .infinity)

                    if index < steps.count - 1 {
                        Capsule()
                            .fill(step.2 ? HaloTheme.lime.opacity(0.55) : Color.white.opacity(0.08))
                            .frame(width: 16, height: 2)
                            .offset(y: -9)
                    }
                }
            }
            .padding(14)
            .haloDarkCard()
        }
    }

    private func reworkPanel(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REWORK")
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(HaloTheme.warning)

                Spacer()

                Text("\(job.unresolvedReworkCount) remaining")
                    .font(HaloType.body(9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.40))
            }

            VStack(alignment: .leading, spacing: 0) {
                if let notes = job.reworkNotes, !notes.isEmpty {
                    Text(notes)
                        .font(HaloType.body(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .padding(.bottom, 12)
                }

                ForEach(job.reworkItems ?? []) { item in
                    Button {
                        toggleRework(job: job, item: item)
                    } label: {
                        HStack(spacing: 12) {
                            if reworkBusy.contains(item.index) {
                                ProgressView()
                                    .tint(HaloTheme.lime)
                                    .frame(width: 22, height: 22)
                            } else {
                                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(item.isComplete ? HaloTheme.lime : HaloTheme.warning)
                            }

                            Text(item.text)
                                .font(HaloType.body(13, weight: .semibold))
                                .foregroundStyle(item.isComplete ? .white.opacity(0.42) : .white)
                                .strikethrough(item.isComplete, color: .white.opacity(0.28))

                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(reworkBusy.contains(item.index))
                }

                if let reworkError {
                    Label(reworkError, systemImage: "exclamationmark.triangle.fill")
                        .font(HaloType.body(10, weight: .semibold))
                        .foregroundStyle(HaloTheme.warning)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .haloDarkCard()
        }
    }

    private func closeoutStatus(_ job: FieldJob) -> some View {
        let stage = job.closeoutStage ?? "active"
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color

        if stage == "history" || job.state == .complete {
            title = "Closed"
            subtitle = "Back Office completed the final closeout."
            icon = "checkmark.seal.fill"
            tint = HaloTheme.success
        } else if job.walkVerified == true || stage == "ready_to_close" {
            title = "Final walk passed"
            subtitle = "Crew work is verified. Office owns the remaining closeout."
            icon = "checkmark.seal.fill"
            tint = HaloTheme.fieldLive
        } else if job.readyForWalk == true {
            title = "Waiting for final walk"
            subtitle = "Work is submitted. Paid work is stopped and the manager owns the next action."
            icon = "person.badge.clock.fill"
            tint = HaloTheme.actionBlue
        } else if stage == "needs_attention" {
            title = "Closeout needs attention"
            subtitle = (job.closeoutBlockers ?? []).first ?? "Back Office has a closeout item that still needs action."
            icon = "exclamationmark.triangle.fill"
            tint = HaloTheme.warning
        } else {
            title = "Closeout in progress"
            subtitle = "HALO is tracking the final review state in Back Office."
            icon = "clock.arrow.circlepath"
            tint = HaloTheme.actionBlue
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("FINAL WALK")
                .font(HaloType.body(10, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(.white.opacity(0.42))

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(HaloType.body(14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(HaloType.body(11))
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer()
            }
            .padding(16)
            .haloDarkCard()
        }
    }

    private func toggleRework(job: FieldJob, item: ReworkItem) {
        guard let token = session.activationToken else {
            reworkError = "This iPhone is not activated."
            return
        }

        reworkBusy.insert(item.index)
        reworkError = nil

        let checked = !item.isComplete
        Task {
            if !network.isConnected {
                await MainActor.run {
                    queueRework(jobID: job.id, index: item.index, checked: checked, token: token)
                }
                return
            }

            do {
                try await HaloAPI.shared.toggleRework(
                    jobID: job.id,
                    index: item.index,
                    checked: checked,
                    activationToken: token
                )
                await store.refresh(activationToken: token)
                await MainActor.run {
                    reworkBusy.remove(item.index)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                let retryable: Bool
                if case HaloAPIError.transport = error {
                    retryable = true
                } else if case let HaloAPIError.http(status, _) = error {
                    retryable = status >= 500 || status == 408 || status == 429
                } else {
                    retryable = false
                }
                if retryable {
                    await MainActor.run {
                        queueRework(jobID: job.id, index: item.index, checked: checked, token: token)
                    }
                    return
                }
                await MainActor.run {
                    reworkBusy.remove(item.index)
                    reworkError = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func queueRework(jobID: String, index: Int, checked: Bool, token: String) {
        OfflineQueue.shared.enqueue(
            jobID: jobID,
            kind: .reworkToggle,
            payload: [
                "index": String(index),
                "checked": String(checked)
            ],
            activationToken: token,
            context: modelContext
        )
        reworkBusy.remove(index)
        reworkError = "Saved offline · rework status will sync automatically."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            HStack {
                Text("CHECKLIST")
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text("\(job.completedTasks)/\(job.tasks.count) DONE")
                    .font(HaloType.body(9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(job.completedTasks == job.tasks.count ? HaloTheme.lime : .white.opacity(0.34))
            }

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
                proofTile(job: job, title: "Before", count: job.beforePhotoCount, done: job.beforePhotoCount > 0)
                proofTile(job: job, title: "After", count: job.afterPhotoCount, done: job.afterPhotoCount > 0)
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


    private func additionalWork(_ job: FieldJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ADDITIONAL WORK")
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                if job.flaggedCount > 0 {
                    Label("\(job.flaggedCount) sent", systemImage: "checkmark.circle.fill")
                        .font(HaloType.body(9, weight: .bold))
                        .foregroundStyle(HaloTheme.lime)
                }
            }

            Button {
                showAdditionalWork = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(HaloTheme.lime.opacity(0.10))
                            .frame(width: 48, height: 48)
                        Image(systemName: "arrow.right.square.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(HaloTheme.lime)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send to Turn Team")
                            .font(HaloType.body(14, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Flag what you found once. HALO carries the unit and job context forward.")
                            .font(HaloType.body(11))
                            .foregroundStyle(.white.opacity(0.42))
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .padding(16)
                .haloDarkCard()
            }
            .buttonStyle(.plain)
        }
    }

    private func propertyNotes(_ job: FieldJob) -> some View {
        Button {
            showMessages = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 44, height: 44)
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HaloTheme.lime)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Need help?")
                        .font(HaloType.body(14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Message the office about this unit.")
                        .font(HaloType.body(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(16)
            .haloDarkCard()
        }
        .buttonStyle(.plain)
    }

    private func primaryAction(_ job: FieldJob) -> some View {
        let actionTitle = (job.state == .enRoute || job.state == .arrived) ? "Photo check-in" : job.state.actionTitle
        let actionIcon = job.state == .scheduled ? "location.fill" : ((job.state == .enRoute || job.state == .arrived) ? "camera.fill" : "arrow.right")

        return Button {
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
                Text(actionTitle)
                Spacer()
                Image(systemName: actionIcon)
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
