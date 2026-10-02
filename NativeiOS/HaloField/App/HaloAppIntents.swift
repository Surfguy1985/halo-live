import AppIntents

struct HaloNextJobIntent: AppIntent {
    static var title: LocalizedStringResource = "What's my next HALO job?"
    static var description = IntentDescription("Shows the next assigned HALO field job.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let job = HaloIntentStore.load() else {
            return .result(dialog: "HALO doesn’t have an assigned job cached on this iPhone yet.")
        }

        return .result(
            dialog: "Your next HALO job is Unit \(job.unit) at \(job.propertyName): \(job.title). It’s scheduled \(job.scheduledWindow)."
        )
    }
}

struct HaloOpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open HALO Today"
    static var description = IntentDescription("Opens HALO to your field work for today.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct HaloAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HaloNextJobIntent(),
            phrases: [
                "What's my next job in \(.applicationName)",
                "Ask \(.applicationName) what's next",
                "What's next in \(.applicationName)"
            ],
            shortTitle: "Next HALO Job",
            systemImageName: "bolt.fill"
        )

        AppShortcut(
            intent: HaloOpenTodayIntent(),
            phrases: [
                "Open \(.applicationName) Today",
                "Show my \(.applicationName) jobs"
            ],
            shortTitle: "Open HALO Today",
            systemImageName: "square.stack.3d.up.fill"
        )
    }
}
