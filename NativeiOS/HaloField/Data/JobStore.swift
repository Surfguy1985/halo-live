import Foundation
import SwiftUI

@MainActor
final class JobStore: ObservableObject {
    @Published private(set) var jobs: [FieldJob] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var syncError: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published var selectedJobID: String?
#if DEBUG
    @Published private(set) var isPreviewMode = false
#endif

    private let api: HaloAPI
    private var hasLoaded = false
    private var loadedToken: String?

    init(api: HaloAPI = .shared) {
        self.api = api
    }

    var nextJob: FieldJob? {
        jobs.first(where: { !$0.isClosed && $0.state != .hold })
            ?? jobs.first(where: { !$0.isClosed })
    }

    var activeJobCount: Int {
        jobs.filter { !$0.isClosed }.count
    }

    var attentionCount: Int {
        jobs.filter { $0.state == .hold || $0.flaggedCount > 0 }.count
    }

    func loadIfNeeded(activationToken: String?) async {
        guard let activationToken, !activationToken.isEmpty else {
            clear()
            return
        }
        guard !hasLoaded || loadedToken != activationToken else { return }
        if loadedToken != nil && loadedToken != activationToken {
            clear()
        }
        await refresh(activationToken: activationToken, initial: true)
    }

    func refresh(activationToken: String?, initial: Bool = false) async {
        if initial { isLoading = true } else { isRefreshing = true }
        defer {
            isLoading = false
            isRefreshing = false
        }

        guard let activationToken, !activationToken.isEmpty else {
            syncError = "This iPhone is not activated for a HALO crew."
            return
        }

        do {
            let live = try await api.fetchJobs(activationToken: activationToken)
            withAnimation(.snappy(duration: 0.28)) {
                jobs = live
            }
            syncError = nil
            lastSyncedAt = .now
            hasLoaded = true
            loadedToken = activationToken
        } catch {
            syncError = error.localizedDescription
        }
    }

#if DEBUG
    func loadPreview() {
        withAnimation(.snappy(duration: 0.28)) {
            jobs = HaloPreviewData.jobs
        }
        syncError = nil
        lastSyncedAt = .now
        hasLoaded = true
        loadedToken = nil
        isPreviewMode = true
    }
#endif

    func clear() {
        jobs = []
        syncError = nil
        lastSyncedAt = nil
        selectedJobID = nil
        hasLoaded = false
        loadedToken = nil
#if DEBUG
        isPreviewMode = false
#endif
    }

    func advance(_ jobID: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let current = jobs[index].state
        let next: JobState = switch current {
        case .scheduled: .enRoute
        case .enRoute: .arrived
        case .arrived: .active
        case .active: .proof
        case .proof: .review
        case .review: .complete
        case .complete: .complete
        case .hold: .hold
        }

        withAnimation(.snappy(duration: 0.35)) {
            jobs[index].state = next
        }
    }

    func recordLocalProof(jobID: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        withAnimation(.snappy(duration: 0.25)) {
            jobs[index].photoCount += 1
        }
    }

    func toggleTask(jobID: String, taskID: String) {
        guard let j = jobs.firstIndex(where: { $0.id == jobID }),
              let t = jobs[j].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        withAnimation(.snappy) {
            jobs[j].tasks[t].isComplete.toggle()
        }
    }
}
