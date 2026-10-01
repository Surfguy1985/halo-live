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
                HaloStatusPill(text: job.scheduledWindow, tint: job.flaggedCount > 0 ? HaloTheme.warning : HaloTheme.actionBlue, icon: "clock.fill")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Unit \(job.unit) · \(job.title)")
                    .font(HaloType.card(hero ? 24 : 19, weight: .bold))
                    .foregroundStyle(.white)
                Text(job.propertyName)
                    .font(HaloType.body(13))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(scopeText)
                    .font(HaloType.body(hero ? 13 : 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(hero ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let notes = job.scopeNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, hero {
                    Label(notes, systemImage: "note.text")
                        .font(HaloType.body(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(2)
                }
            }

            VStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [HaloTheme.lime, HaloTheme.fieldLive], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, proxy.size.width * job.progress))
                    }
                }
                .frame(height: 5)
                HStack {
                    Text("\(job.completedTasks) of \(job.tasks.count) tasks")
                    Spacer()
                    Text("\(Int((job.progress * 100).rounded()))%")
                }
                .font(HaloType.body(9, weight: .bold))
                .foregroundStyle(.white.opacity(0.38))
            }

            HStack(spacing: 12) {
                Label("\(job.completedTasks)/\(job.tasks.count)", systemImage: "checkmark.circle")
                Label("\(job.photoCount)", systemImage: "camera")
                if job.flaggedCount > 0 {
                    Label("\(job.flaggedCount)", systemImage: "flag.fill")
                        .foregroundStyle(HaloTheme.warning)
                }
                Spacer()
                if let travel = job.travelMinutes {
                    Label("\(travel) min", systemImage: "location")
                }
            }
            .font(HaloType.body(10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.50))

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
        .padding(hero ? 20 : 16)
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