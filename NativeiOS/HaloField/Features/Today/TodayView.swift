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
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(HaloTheme.muted)

                        NavigationLink {
                            JobDetailView(jobID: next.id)
                        } label: {
                            FieldJobCard(job: next, hero: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Up next").font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(store.jobs.filter { $0.state != .complete }.count) today")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    ForEach(store.jobs.dropFirst()) { job in
                        NavigationLink {
                            JobDetailView(jobID: job.id)
                        } label: {
                            FieldJobCard(job: job, hero: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, HaloTheme.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(HaloTheme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Good morning")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HaloTheme.muted)
                    Text("Ready to move.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .tracking(-0.8)
                }
                Spacer()
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(HaloTheme.ink)
            }

            HStack(spacing: 8) {
                Label("3 jobs", systemImage: "briefcase.fill")
                Text("•")
                Label("1 needs attention", systemImage: "exclamationmark.circle.fill")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(HaloTheme.muted)
        }
    }
}
