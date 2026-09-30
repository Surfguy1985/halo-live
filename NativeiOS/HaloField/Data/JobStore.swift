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
    private let cache: OfflineJobCache
    private var hasLoaded = false
    private var loadedToken: String?

    init(api: HaloAPI = .shared, cache: OfflineJobCache = .shared) {
        self.api = api
        self.cache = cache
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

        if jobs.isEmpty, let snapshot = try? await cache.load(token: activationToken) {
            withAnimation(.snappy(duration: 0.22)) {
                jobs = snapshot.jobs
                HaloIntentStore.save(nextJob)
            }
            lastSyncedAt = snapshot.savedAt
            loadedToken = activationToken
            syncError = "Offline-ready cache loaded. Refreshing live HALO…"
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
                HaloIntentStore.save(nextJob)
            }
            syncError = nil
            lastSyncedAt = .now
            hasLoaded = true
            loadedToken = activationToken
            try? await cache.save(jobs: live, token: activationToken)
        } catch {
            if jobs.isEmpty {
                syncError = error.localizedDescription
            } else {
                syncError = "Offline — showing your last synced HALO jobs. New work will sync when service returns."
                hasLoaded = true
                loadedToken = activationToken
            }
        }
    }

#if DEBUG
    func loadPreview() {
        withAnimation(.snappy(duration: 0.28)) {
            jobs = HaloPreviewData.jobs
            HaloIntentStore.save(nextJob)
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
        HaloIntentStore.save(nil)
        syncError = nil
        lastSyncedAt = nil
        selectedJobID = nil
        hasLoaded = false
        loadedToken = nil
#if DEBUG
        isPreviewMode = false
#endif
    }

    func setState(_ state: JobState, for jobID: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        withAnimation(.snappy(duration: 0.35)) {
            jobs[index].state = state
            HaloIntentStore.save(nextJob)
        }
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
            HaloIntentStore.save(nextJob)
        }
    }

    func recordHandoff(jobID: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        withAnimation(.snappy(duration: 0.25)) {
            jobs[index].flaggedCount += 1
        }
    }

    func recordLocalProof(jobID: String, phase: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        withAnimation(.snappy(duration: 0.25)) {
            jobs[index].photoCount += 1
            if phase.lowercased() == "after" {
                jobs[index].afterPhotoCount += 1
            } else {
                jobs[index].beforePhotoCount += 1
            }
            HaloIntentStore.save(nextJob)
        }
    }

    func toggleTask(jobID: String, taskID: String) {
        guard let j = jobs.firstIndex(where: { $0.id == jobID }),
              let t = jobs[j].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        withAnimation(.snappy) {
            jobs[j].tasks[t].isComplete.toggle()
            HaloIntentStore.save(nextJob)
        }
    }
}
