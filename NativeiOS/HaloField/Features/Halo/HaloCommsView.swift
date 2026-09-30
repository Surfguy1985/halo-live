import CoreLocation
import SwiftUI
import UIKit

struct HaloCommsView: View {
    var initialJobID: String? = nil
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var store: JobStore

    @State private var messages: [HaloMessage] = []
    @State private var gpsSessions: [HaloGPSSession] = []
    @State private var sharing = Set<String>()
    @State private var lastSent: [String: Date] = [:]
    @State private var selectedJobID: String?
    @State private var selectedThreadChannel: String?
    @State private var selectedThreadName: String?
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    if !gpsSessions.isEmpty {
                        liveLocationSection
                    }
                    inboxSection
                    composer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(HaloTheme.fieldBackground.ignoresSafeArea())
            .navigationTitle("Halo")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable { await refresh() }
            .task(id: session.activationToken) {
                if selectedJobID == nil { selectedJobID = initialJobID }
                await refresh()

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    if network.isConnected {
                        await refresh()
                    }
                }
            }
            .onReceive(location.$location) { fix in
                guard let fix else { return }
                sendLiveLocation(fix)
            }
            .onChange(of: messages.count) { _, _ in
                if let id = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(HaloTheme.lime)
                    .frame(width: 54, height: 54)
                Image(systemName: "message.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HaloTheme.ink)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("FIELD COMMS")
                    .font(HaloType.body(9, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(HaloTheme.lime)
                Text("Office ↔ Crew")
                    .font(HaloType.display(26, weight: .semibold))
                    .foregroundStyle(.white)
                Text(network.isConnected ? "Live with Halo Back Office" : "Offline · messages unavailable")
                    .font(HaloType.body(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            if isLoading {
                ProgressView().tint(HaloTheme.lime)
            }
        }
        .padding(.top, 6)
    }

    private var liveLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("LIVE LOCATION REQUESTS")

            ForEach(gpsSessions) { item in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(sharing.contains(item.id) ? HaloTheme.fieldLive.opacity(0.14) : HaloTheme.actionBlue.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: sharing.contains(item.id) ? "location.fill" : "location.circle.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(sharing.contains(item.id) ? HaloTheme.fieldLive : HaloTheme.actionBlue)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.property ?? "Live location requested")
                                .font(HaloType.body(14, weight: .bold))
                                .foregroundStyle(.white)
                            Text(item.unitNumber.map { "Unit \($0)" } ?? "Dispatch requested your location")
                                .font(HaloType.body(11))
                                .foregroundStyle(.white.opacity(0.46))
                        }

                        Spacer()

                        if sharing.contains(item.id) {
                            Text("LIVE")
                                .font(HaloType.body(9, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(HaloTheme.fieldLive)
                        }
                    }

                    HStack(spacing: 10) {
                        if sharing.contains(item.id) {
                            Button {
                                stopSharing(item)
                            } label: {
                                Label("Stop Sharing", systemImage: "stop.fill")
                                    .font(HaloType.body(12, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(Color.white.opacity(0.07))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Button {
                                startSharing(item)
                            } label: {
                                Label("Share Live Location", systemImage: "location.fill")
                                    .font(HaloType.body(12, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(HaloTheme.lime)
                                    .foregroundStyle(HaloTheme.ink)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Text(sharing.contains(item.id)
                         ? "Your GPS is shared only while this request is active. You can stop anytime."
                         : "HALO never begins live sharing until you choose to start it.")
                        .font(HaloType.body(9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.34))
                }
                .padding(16)
                .haloDarkCard()
            }
        }
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("MESSAGES")
                Spacer()
                if !messages.isEmpty {
                    Text("\(messages.count) recent")
                        .font(HaloType.body(9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }

            if messages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                    Text("No field messages yet")
                        .font(HaloType.body(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    Text("Office updates and unit-linked conversations will appear here.")
                        .font(HaloType.body(10))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.32))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .haloDarkCard()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(messages.sorted(by: { ($0.at ?? "") < ($1.at ?? "") })) { message in
                        messageBubble(message)
                            .id(message.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if message.channel.hasPrefix("group:") {
                                    selectedThreadChannel = message.channel
                                    selectedThreadName = message.threadName
                                    if let unitID = message.unitID {
                                        selectedJobID = unitID
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(HaloType.body(10, weight: .semibold))
                    .foregroundStyle(HaloTheme.warning)
            }
        }
    }

    private func messageBubble(_ message: HaloMessage) -> some View {
        let outgoing = message.from == "field"
        return HStack {
            if outgoing { Spacer(minLength: 52) }

            VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let thread = message.threadName, !thread.isEmpty {
                        Text(thread.uppercased())
                            .font(HaloType.body(8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.52) : HaloTheme.actionBlue)
                    }
                    if let unit = message.unitLabel, !unit.isEmpty {
                        Text(unit)
                            .font(HaloType.body(8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.58) : HaloTheme.lime)
                    }
                    Text(message.author)
                        .font(HaloType.body(9, weight: .bold))
                        .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.48) : .white.opacity(0.38))
                }

                Text(message.text)
                    .font(HaloType.body(13, weight: .medium))
                    .foregroundStyle(outgoing ? HaloTheme.ink : .white)
                    .multilineTextAlignment(outgoing ? .trailing : .leading)

                if !message.attachments.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            attachmentView(attachment, outgoing: outgoing)
                        }
                    }
                    .padding(.top, 4)
                }

                if let at = message.at {
                    Text(displayTime(at))
                        .font(HaloType.body(8, weight: .medium))
                        .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.35) : .white.opacity(0.28))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(outgoing ? HaloTheme.lime : HaloTheme.fieldCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if !outgoing {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(HaloTheme.fieldBorder, lineWidth: 1)
                }
            }

            if !outgoing { Spacer(minLength: 52) }
        }
    }

    @ViewBuilder
    private func attachmentView(_ attachment: HaloMessageAttachment, outgoing: Bool) -> some View {
        if !attachment.proofPairs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(attachment.title ?? "Before & After")
                    .font(HaloType.body(10, weight: .bold))
                    .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.72) : .white.opacity(0.78))

                ForEach(attachment.proofPairs.prefix(6)) { pair in
                    VStack(alignment: .leading, spacing: 6) {
                        if let area = pair.area, !area.isEmpty {
                            Text(area.uppercased())
                                .font(HaloType.body(8, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.44) : .white.opacity(0.38))
                        }

                        HStack(spacing: 6) {
                            if let before = pair.beforeURL {
                                proofImage(urlString: before, label: "Before")
                            }
                            if let after = pair.afterURL {
                                proofImage(urlString: after, label: "After")
                            }
                        }
                    }
                }
            }
            .padding(9)
            .background(outgoing ? Color.black.opacity(0.07) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let before = attachment.beforeURL, let after = attachment.afterURL {
            VStack(alignment: .leading, spacing: 8) {
                Text(attachment.title ?? "Before & After")
                    .font(HaloType.body(10, weight: .bold))
                    .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.72) : .white.opacity(0.78))

                HStack(spacing: 6) {
                    proofImage(urlString: before, label: "Before")
                    proofImage(urlString: after, label: "After")
                }
            }
            .padding(9)
            .background(outgoing ? Color.black.opacity(0.07) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if attachment.kind == "image", let url = attachment.url {
            VStack(alignment: .leading, spacing: 5) {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()
                    default:
                        ZStack {
                            Color.white.opacity(0.06)
                            ProgressView()
                                .tint(outgoing ? HaloTheme.ink : .white)
                        }
                        .frame(height: 160)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let caption = attachment.caption {
                    Text(caption.uppercased())
                        .font(HaloType.body(8, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.50) : .white.opacity(0.42))
                }
            }
        } else if attachment.kind == "card" || attachment.kind == "module" {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(outgoing ? Color.black.opacity(0.08) : HaloTheme.lime.opacity(0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: cardIcon(for: attachment))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(outgoing ? HaloTheme.ink : HaloTheme.lime)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.title ?? attachment.name ?? "HALO update")
                        .font(HaloType.body(11, weight: .bold))
                        .foregroundStyle(outgoing ? HaloTheme.ink : .white)

                    if let summary = attachment.actionSummary, !summary.isEmpty {
                        Text(summary)
                            .font(HaloType.body(9, weight: .medium))
                            .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.54) : .white.opacity(0.46))
                    }

                    HStack(spacing: 7) {
                        if let status = attachment.status, !status.isEmpty {
                            Text(status.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(HaloType.body(8, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.56) : HaloTheme.fieldLive)
                        }
                        if let action = attachment.actionTitle, !action.isEmpty {
                            Text(action)
                                .font(HaloType.body(8, weight: .bold))
                                .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.70) : HaloTheme.lime)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(outgoing ? Color.black.opacity(0.06) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let name = attachment.name {
            Label(name, systemImage: "doc.fill")
                .font(HaloType.body(10, weight: .semibold))
                .foregroundStyle(outgoing ? HaloTheme.ink.opacity(0.72) : .white.opacity(0.70))
                .padding(10)
                .background(outgoing ? Color.black.opacity(0.06) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func proofImage(urlString: String, label: String) -> some View {
        VStack(spacing: 5) {
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: "photo")
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(label.uppercased())
                .font(HaloType.body(8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity)
    }

    private func cardIcon(for attachment: HaloMessageAttachment) -> String {
        let haystack = [
            attachment.title,
            attachment.status,
            attachment.actionTitle,
            attachment.actionSummary
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        if haystack.contains("approval") || haystack.contains("approve") { return "checkmark.seal.fill" }
        if haystack.contains("flag") { return "flag.fill" }
        if haystack.contains("photo") { return "photo.on.rectangle.angled" }
        if haystack.contains("rework") { return "arrow.counterclockwise.circle.fill" }
        return "rectangle.stack.fill"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("REPLY TO OFFICE")

            Menu {
                Button("General message") {
                    selectedJobID = nil
                    selectedThreadChannel = nil
                    selectedThreadName = nil
                }

                if let selectedThreadName, selectedThreadChannel != nil {
                    Button("Reply in \(selectedThreadName)") {
                        selectedJobID = nil
                    }
                }
                ForEach(store.jobs.filter { !$0.isClosed }) { job in
                    Button("Unit \(job.unit) · \(job.propertyName)") {
                        selectedJobID = job.id
                        selectedThreadChannel = nil
                        selectedThreadName = nil
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text(selectedJobLabel)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(HaloType.body(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message the office…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(HaloType.body(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    send()
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(HaloTheme.ink)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(canSend ? HaloTheme.lime : Color.white.opacity(0.08))
                    .foregroundStyle(canSend ? HaloTheme.ink : .white.opacity(0.28))
                    .clipShape(Circle())
                }
                .disabled(!canSend || isSending)
                .accessibilityLabel("Send message")
            }
        }
    }

    private var canSend: Bool {
        network.isConnected && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedJobLabel: String {
        if let selectedThreadName, selectedThreadChannel != nil {
            return "Thread · \(selectedThreadName)"
        }
        guard let selectedJobID, let job = store.jobs.first(where: { $0.id == selectedJobID }) else {
            return "General · Office"
        }
        return "Unit \(job.unit) · \(job.propertyName)"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(HaloType.body(9, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.38))
    }

    private func displayTime(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // Foreground refresh keeps Back Office messages and location requests feeling live
    // without requiring a permanent socket connection.
    private func refresh() async {
        guard network.isConnected, let token = session.activationToken, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let messageRequest = HaloAPI.shared.fetchMessages(activationToken: token)
            async let gpsRequest = HaloAPI.shared.fetchGPSSessions(activationToken: token)
            let (newMessages, newSessions) = try await (messageRequest, gpsRequest)
            messages = newMessages
            gpsSessions = newSessions
            sharing = Set(newSessions.filter { $0.consentedAt != nil && $0.active }.map(\.id))
            errorMessage = nil

            if !sharing.isEmpty {
                location.requestPermission()
                location.startLiveSharing()
                location.refresh()
            } else {
                location.stopLiveSharing()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startSharing(_ item: HaloGPSSession) {
        location.requestPermission()
        location.startLiveSharing()
        location.refresh()
        sharing.insert(item.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let fix = location.freshLocation(requiredAccuracy: 150) {
            Task { await update(item, fix: fix) }
        }
    }

    private func stopSharing(_ item: HaloGPSSession) {
        guard let token = session.activationToken else { return }
        Task {
            do {
                try await HaloAPI.shared.stopGPSSession(id: item.id, activationToken: token)
                await MainActor.run {
                    sharing.remove(item.id)
                    gpsSessions.removeAll { $0.id == item.id }
                    if sharing.isEmpty { location.stopLiveSharing() }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func sendLiveLocation(_ fix: CLLocation) {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 150 else { return }
        for item in gpsSessions where sharing.contains(item.id) {
            let prior = lastSent[item.id] ?? .distantPast
            guard Date().timeIntervalSince(prior) >= 15 else { continue }
            lastSent[item.id] = .now
            Task { await update(item, fix: fix) }
        }
    }

    private func update(_ item: HaloGPSSession, fix: CLLocation) async {
        guard let token = session.activationToken else { return }
        do {
            try await HaloAPI.shared.updateGPSSession(id: item.id, location: fix, activationToken: token)
            await MainActor.run { errorMessage = nil }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                sharing.remove(item.id)
                if sharing.isEmpty { location.stopLiveSharing() }
            }
        }
    }

    private func send() {
        guard canSend, let token = session.activationToken else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                try await HaloAPI.shared.sendMessage(
                    text: text,
                    jobID: selectedJobID,
                    channel: selectedThreadChannel,
                    activationToken: token
                )
                await MainActor.run {
                    draft = ""
                    isSending = false
                }
                await refresh()
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
