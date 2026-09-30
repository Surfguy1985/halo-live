import SwiftUI

struct FieldJobCard: View {
    let job: FieldJob
    let hero: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: hero ? 18 : 14) {
            HStack(alignment: .center) {
                Text(job.kind.rawValue)
                    .font(.caption2.weight(.black))
                    .tracking(1.2)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(job.kind == .turn ? HaloTheme.ink : HaloTheme.gold.opacity(0.22))
                    .foregroundStyle(job.kind == .turn ? .white : HaloTheme.ink)
                    .clipShape(Capsule())
                Spacer()
                Text(job.scheduledWindow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Unit \(job.unit) · \(job.title)")
                    .font(.system(size: hero ? 24 : 19, weight: .bold, design: .rounded))
                    .foregroundStyle(HaloTheme.ink)
                Text(job.propertyName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: job.progress)
                .tint(HaloTheme.ink)
                .scaleEffect(x: 1, y: 1.7, anchor: .center)

            HStack(spacing: 16) {
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(HaloTheme.muted)

            if hero {
                HStack {
                    Text(job.state.actionTitle)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.headline)
                .padding(.horizontal, 18).frame(height: 54)
                .foregroundStyle(.white)
                .background(HaloTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: HaloTheme.controlRadius, style: .continuous))
            }
        }
        .padding(hero ? 20 : 18)
        .haloCard()
    }
}
