import SwiftUI

struct FieldJobCard: View {
    let job: FieldJob
    let hero: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: hero ? 18 : 14) {
            HStack {
                Text(job.kind.rawValue)
                    .font(HaloType.body(9, weight: .bold))
                    .tracking(1.4)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(job.kind == .turn ? HaloTheme.lime : Color.white.opacity(0.10))
                    .foregroundStyle(job.kind == .turn ? HaloTheme.ink : .white)
                    .clipShape(Capsule())
                Spacer()
                Text(job.scheduledWindow)
                    .font(HaloType.body(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.44))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Unit \(job.unit) · \(job.title)")
                    .font(HaloType.card(hero ? 24 : 19, weight: .bold))
                    .foregroundStyle(.white)
                Text(job.propertyName)
                    .font(HaloType.body(13))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("FULL SCOPE")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(HaloTheme.lime)
                    Spacer()
                    Text("\(job.scopeItemCount) ITEM\(job.scopeItemCount == 1 ? "" : "S")")
                        .font(HaloType.body(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.34))
                }

                Text(scopeText)
                    .font(HaloType.body(hero ? 12 : 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                if let notes = job.scopeNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(HaloType.body(10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(13)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            ProgressView(value: job.progress)
                .tint(HaloTheme.lime)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)

            HStack(spacing: 15) {
                Label("\(job.completedTasks)/\(job.tasks.count)", systemImage: "checkmark.circle.fill")
                Label("\(job.photoCount)", systemImage: "camera.fill")
                if job.flaggedCount > 0 {
                    Label("\(job.flaggedCount)", systemImage: "flag.fill").foregroundStyle(.orange)
                }
                Spacer()
                if let travel = job.travelMinutes {
                    Label("\(travel) min", systemImage: "location.fill")
                }
            }
            .font(HaloType.body(10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.48))

            if hero {
                HStack {
                    Text(job.state.actionTitle)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(HaloType.body(15, weight: .bold))
                .padding(.horizontal, 18).frame(height: 56)
                .foregroundStyle(HaloTheme.ink)
                .background(HaloTheme.lime)
                .clipShape(Capsule())
                .shadow(color: HaloTheme.lime.opacity(0.16), radius: 20, y: 8)
            }
        }
        .padding(hero ? 20 : 18)
        .haloDarkCard()
    }
 
    private var scopeText: String {
        let services = job.services
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !services.isEmpty {
            return services.joined(separator: "  •  ")
        }

        let tasks = job.tasks
            .map(\.title)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return tasks.isEmpty ? "Scope pending from Back Office" : tasks.joined(separator: "  •  ")
    }

}