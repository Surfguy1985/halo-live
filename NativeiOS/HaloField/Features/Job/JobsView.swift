import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var session: HaloSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filtersExpanded = false
    @State private var scope: JobBrowserScope = .assigned
    @State private var query = JobBrowserQuery()
    @State private var remoteJobs: [FieldJob] = []
    @State private var loading = false
    @State private var error: String?
    @State private var syncedAt: Date?
    @State private var requestID = UUID()

    private var availableScopes: [JobBrowserScope] { JobBrowserScope.available(officeAccess: session.officeAccess) }
    private var source: [FieldJob] { scope == .assigned ? store.jobs : remoteJobs }
    private var visible: [FieldJob] { query.apply(to: source) }
    private var properties: [String] { Array(Set(source.map(\.propertyName))).sorted() }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HaloSectionLabel(title: session.officeAccess ? "Office workspace" : "Your briefing")
                    Text(session.officeAccess ? "Every unit. One view." : "Your work, organized.")
                        .font(HaloType.display(26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(session.officeAccess ? "Find open work, review completed jobs, and focus on what needs attention." : "Search and organize the jobs assigned to your crew.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }.padding(.vertical, 8)
                if availableScopes.count > 1 {
                    Picker("Job board", selection: $scope) {
                        ForEach(availableScopes) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }

                HaloExpandablePanel(title: "Filter & sort", icon: "line.3.horizontal.decrease", badge: query.attentionOnly ? "Attention" : query.sort.rawValue, expanded: $filtersExpanded) {
                    filters
                }
                if session.officeAccess && scope == .assigned { TurnsPickupView() }

                if let message = scope == .assigned ? store.syncError : error {
                    Label(message, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(HaloType.body(12)).foregroundStyle(HaloTheme.warning)
                        .padding(14).haloDarkCard()
                }
                HStack {
                    Text("\(visible.count) of \(source.count) jobs")
                    Spacer()
                    if let date = scope == .assigned ? store.lastSyncedAt : syncedAt {
                        Text(date, style: .relative) + Text(" ago")
                    }
                }.font(HaloType.body(11, weight: .medium)).foregroundStyle(.white.opacity(0.5))

                if loading || (scope == .assigned && store.isLoading) {
                    ProgressView("Refreshing jobs…").frame(maxWidth: .infinity).padding(24)
                }
                if visible.isEmpty && !loading && !store.isLoading {
                    ContentUnavailableView {
                        Label(source.isEmpty ? "No jobs here yet" : "No matching jobs", systemImage: "tray")
                    } description: {
                        Text(source.isEmpty ? emptyMessage : "Try another property, service, or unit number.")
                    } actions: {
                        if !source.isEmpty { Button("Clear filters") { query = JobBrowserQuery() } }
                        Button("Refresh") { Task { await refresh() } }
                    }
                }
                ForEach(visible) { job in
                    NavigationLink {
                        if scope != .history && store.jobs.contains(where: { $0.id == job.id && !$0.isClosed }) {
                            JobDetailView(jobID: job.id)
                        } else {
                            JobRecordView(job: job)
                        }
                    } label: {
                        FieldJobCard(job: job, hero: false)
                    }.buttonStyle(HaloPressableStyle())
                }
            }.padding(16)
        }
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .navigationTitle("Jobs")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $query.text, prompt: "Property, unit, service or scope")
        .refreshable { await refresh() }
        .task(id: scope) {
            query.property = ""
            query.attentionOnly = false
            remoteJobs = []
            syncedAt = nil
            error = nil
            await refresh()
        }
        .onChange(of: session.officeAccess) { _, allowed in
            guard !allowed else { return }
            requestID = UUID()
            remoteJobs = []
            syncedAt = nil
            loading = false
            scope = .assigned
        }
        .onChange(of: session.activationToken) { _, _ in
            requestID = UUID()
            remoteJobs = []
            syncedAt = nil
            error = nil
            loading = false
            scope = .assigned
        }
        .navigationDestination(isPresented: Binding(
            get: { store.selectedJobID != nil },
            set: { if !$0 { store.selectedJobID = nil } }
        )) {
            if let jobID = store.selectedJobID { JobDetailView(jobID: jobID) }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Work type", selection: $query.kind) {
                Text("All work").tag(nil as JobKind?)
                Text("Turns").tag(JobKind.turn as JobKind?)
                Text("Maintenance").tag(JobKind.maintenance as JobKind?)
            }.pickerStyle(.segmented)
            HStack {
                Menu {
                    Picker("Property", selection: $query.property) {
                        Text("All properties").tag("")
                        ForEach(properties, id: \.self) { Text($0).tag($0) }
                    }
                } label: { Label(query.property.isEmpty ? "All properties" : query.property, systemImage: "building.2") }
                Spacer()
                Menu {
                    Picker("Sort jobs", selection: $query.sort) {
                        ForEach(JobBrowserSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label(query.sort.rawValue, systemImage: "arrow.up.arrow.down") }
            }.font(HaloType.body(12, weight: .semibold)).tint(HaloTheme.lime)
            if scope != .history {
                Toggle("Needs attention", isOn: $query.attentionOnly)
                    .font(HaloType.body(12, weight: .medium)).tint(HaloTheme.actionBlue)
            }
        }.padding(.top, 12)
    }

    private var emptyMessage: String {
        switch scope {
        case .assigned: "Assigned work appears here when Dispatch adds your crew."
        case .board: "Open turns and maintenance authorized for your office appear here."
        case .history: "Completed jobs remain available here for reference."
        }
    }

    @MainActor private func refresh() async {
        let id = UUID()
        requestID = id
        let requestedScope = scope
        guard availableScopes.contains(requestedScope), let token = session.activationToken else {
            loading = false
            return
        }
        if requestedScope == .assigned {
            loading = false
            await store.refresh(activationToken: token)
            return
        }
        loading = true
        defer { if requestID == id { loading = false } }
        do {
            let jobs = try await HaloAPI.shared.fetchJobs(activationToken: token, scope: requestedScope.apiValue)
            guard !Task.isCancelled, requestID == id, session.activationToken == token, availableScopes.contains(requestedScope) else { return }
            remoteJobs = jobs
            syncedAt = .now
            error = nil
        } catch {
            guard !Task.isCancelled, requestID == id, session.activationToken == token, availableScopes.contains(requestedScope) else { return }
            self.error = error.localizedDescription
        }
    }
}

// Board and historical records are intentionally read-only. Assignment and
// work authorization continue to be enforced by the native action gateway.
struct JobRecordView: View {
    let job: FieldJob
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FieldJobCard(job: job, hero: true)
                Label(job.isClosed ? "Completed work · read only" : "Property board · read only", systemImage: "lock")
                    .font(HaloType.body(12)).foregroundStyle(HaloTheme.lime)
                if !job.isClosed {
                    Text("Dispatch must assign this job to your crew before you can clock in or record work.")
                        .font(HaloType.body(13)).foregroundStyle(.secondary)
                }
                GroupBox("Full scope · \(job.scopeItemCount) items") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(job.tasks) { task in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                    if let detail = task.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                }
                            } icon: { Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle") }
                        }
                        if let notes = job.scopeNotes, !notes.isEmpty { Divider(); Text(notes).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                GroupBox("Job details") {
                    VStack(spacing: 12) {
                        LabeledContent("Property", value: job.propertyName)
                        LabeledContent("Address", value: job.address)
                        LabeledContent("Scheduled", value: job.scheduledWindow)
                        LabeledContent("Before photos", value: "\(job.beforePhotoCount)")
                        LabeledContent("After photos", value: "\(job.afterPhotoCount)")
                        LabeledContent("Flagged items", value: "\(job.flaggedCount)")
                        if let stage = job.closeoutStage { LabeledContent("Closeout", value: stage.replacingOccurrences(of: "_", with: " ")) }
                    }.font(HaloType.body(12)).padding(.top, 8)
                }
                if let notes = job.reworkNotes, !notes.isEmpty { GroupBox("Rework notes") { Text(notes).frame(maxWidth: .infinity, alignment: .leading) } }
                if let blockers = job.closeoutBlockers, !blockers.isEmpty {
                    GroupBox("Closeout blockers") {
                        VStack(alignment: .leading) { ForEach(Array(blockers.enumerated()), id: \.offset) { _, text in Label(text, systemImage: "exclamationmark.circle") } }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(16)
        }
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .navigationTitle("Unit \(job.unit)").navigationBarTitleDisplayMode(.inline)
    }
}
