import ActivityKit
import Foundation
import HaloShared

@MainActor
final class HaloLiveActivityController: ObservableObject {
    @Published private(set) var activeJobID: String?
    @Published private(set) var isLive = false

    func startOrUpdate(job: FieldJob) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let activity = Activity<HaloJobActivityAttributes>.activities.first(where: { $0.attributes.jobID == job.id }) {
            await activity.update(
                ActivityContent(
                    state: contentState(for: job),
                    staleDate: Date().addingTimeInterval(60 * 30)
                )
            )
            activeJobID = job.id
            isLive = true
            return
        }

        if let other = Activity<HaloJobActivityAttributes>.activities.first {
            await other.end(
                ActivityContent(
                    state: other.content.state,
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
        }

        do {
            let activity = try Activity.request(
                attributes: HaloJobActivityAttributes(
                    jobID: job.id,
                    unit: job.unit,
                    propertyName: job.propertyName,
                    title: job.title
                ),
                content: ActivityContent(
                    state: contentState(for: job),
                    staleDate: Date().addingTimeInterval(60 * 30)
                ),
                pushType: nil
            )
            activeJobID = activity.attributes.jobID
            isLive = true
        } catch {
            activeJobID = nil
            isLive = false
        }
    }

    func end(job: FieldJob) async {
        guard let activity = Activity<HaloJobActivityAttributes>.activities.first(where: { $0.attributes.jobID == job.id }) else {
            if activeJobID == job.id {
                activeJobID = nil
                isLive = false
            }
            return
        }

        await activity.end(
            ActivityContent(
                state: contentState(for: job),
                staleDate: nil
            ),
            dismissalPolicy: .default
        )

        activeJobID = nil
        isLive = false
    }

    func restoreState() {
        let active = Activity<HaloJobActivityAttributes>.activities.first
        activeJobID = active?.attributes.jobID
        isLive = active != nil
    }

    private func contentState(for job: FieldJob) -> HaloJobActivityAttributes.ContentState {
        HaloJobActivityAttributes.ContentState(
            state: job.state.rawValue,
            progress: job.progress,
            completedTasks: job.completedTasks,
            totalTasks: job.tasks.count,
            photoCount: job.photoCount,
            nextAction: job.state.actionTitle
        )
    }
}
