import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: JobStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let next = store.nextJob {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NEXT JOB")
                            .font(HaloType.body(10, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.42))

                        NavigationLink { JobDetailView(jobID: next.id) } label: {
                            FieldJobCard(job: next, hero: true)
                        }.buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Up next").font(HaloType.display(20, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(store.jobs.filter { $0.state != .complete }.count) today")
                            .font(HaloType.body(12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    }

                    ForEach(store.jobs.dropFirst()) { job in
                        NavigationLink { JobDetailView(jobID: job.id) } label: {
                            FieldJobCard(job: job, hero: false)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, HaloTheme.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(
            ZStack {
                HaloTheme.fieldBackground
                RadialGradient(colors: [HaloTheme.actionBlue.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 360)
            }.ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HaloLogo(height: 27)
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(HaloTheme.fieldLive).frame(width: 7, height: 7)
                    Text("LIVE").font(HaloType.body(10, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GOOD MORNING")
                    .font(HaloType.body(10, weight: .bold)).tracking(1.8).foregroundStyle(.white.opacity(0.4))
                Text("Ready to move.")
                    .font(HaloType.display(34, weight: .semibold))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                Label("3 jobs", systemImage: "briefcase.fill")
                Text("•")
                Label("1 needs attention", systemImage: "exclamationmark.circle.fill")
            }
            .font(HaloType.body(12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}