import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore

    init() {
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.45)
        UITabBar.appearance().backgroundColor = UIColor(red: 9/255, green: 23/255, blue: 34/255, alpha: 0.98)
    }

    var body: some View {
        Group {
            if session.isActivated {
                tabShell
            } else {
                ActivationView()
            }
        }
        .task(id: session.activationToken) {
            guard session.isActivated else {
                store.clear()
                return
            }
            await store.loadIfNeeded(activationToken: session.activationToken)
        }
    }

    private var tabShell: some View {
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
        .tint(HaloTheme.lime)
    }
}

private struct JobsView: View {
    @EnvironmentObject var store: JobStore
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.jobs) { job in
                    NavigationLink { JobDetailView(jobID: job.id) } label: {
                        FieldJobCard(job: job, hero: false)
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .navigationTitle("Jobs")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct HaloAssistantView: View {
    @State private var text = ""
    var body: some View {
        VStack(spacing: 18) {
            HaloLogo(height: 30)
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 38, weight: .medium)).foregroundStyle(HaloTheme.lime)
            Text("Ask HALO").font(HaloType.display(30, weight: .semibold)).foregroundStyle(.white)
            Text("Jobs, instructions, property notes, handoffs, or what to do next.")
                .font(HaloType.body(14)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.5))
            Spacer()
            HStack {
                TextField("Ask about your work…", text: $text).foregroundStyle(.white)
                Button { } label: {
                    Image(systemName: "arrow.up").fontWeight(.bold)
                        .frame(width: 40, height: 40)
                        .background(HaloTheme.lime).foregroundStyle(HaloTheme.ink).clipShape(Circle())
                }
            }
            .padding(10).background(Color.white.opacity(0.06)).clipShape(Capsule())
            .overlay(Capsule().stroke(HaloTheme.fieldBorder))
        }
        .padding(HaloTheme.horizontal)
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore

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
                Button(role: .destructive) {
                    store.clear()
                    session.deactivate()
                } label: {
                    Label("Deactivate this iPhone", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HaloTheme.fieldBackground)
        .navigationTitle("Me")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}