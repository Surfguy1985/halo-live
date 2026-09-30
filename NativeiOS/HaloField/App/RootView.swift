import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "bolt.fill") }

            NavigationStack { JobsView() }
                .tabItem { Label("Jobs", systemImage: "square.stack.3d.up.fill") }

            NavigationStack { HaloAssistantView() }
                .tabItem { Label("Halo", systemImage: "sparkles") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(HaloTheme.ink)
    }
}

private struct JobsView: View {
    @EnvironmentObject var store: JobStore
    var body: some View {
        List(store.jobs) { job in
            NavigationLink { JobDetailView(jobID: job.id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(job.unit) · \(job.title)").font(.headline)
                    Text(job.propertyName).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Jobs")
    }
}

private struct HaloAssistantView: View {
    @State private var text = ""
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 38, weight: .medium))
            Text("Ask HALO").font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("Jobs, instructions, property notes, handoffs, or what to do next.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            HStack {
                TextField("Ask about your work…", text: $text)
                Button { } label: {
                    Image(systemName: "arrow.up").fontWeight(.bold)
                        .frame(width: 38, height: 38)
                        .background(HaloTheme.ink).foregroundStyle(.white).clipShape(Circle())
                }
            }
            .padding(10).background(.white).clipShape(Capsule())
            .overlay(Capsule().stroke(HaloTheme.hairline))
        }
        .padding(HaloTheme.horizontal)
        .background(HaloTheme.paper.ignoresSafeArea())
        .navigationTitle("Halo")
    }
}

private struct ProfileView: View {
    var body: some View {
        List {
            Section("Field") {
                Label("Offline sync", systemImage: "arrow.triangle.2.circlepath")
                Label("Location verification", systemImage: "location.fill")
                Label("Notifications", systemImage: "bell.fill")
            }
            Section("Account") {
                Label("Crew profile", systemImage: "person.2.fill")
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .navigationTitle("Me")
    }
}
