import CoreLocation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum HaloConversationMode: String, CaseIterable, Identifiable {
    case office = "Crew Chat"
    case ai = "Halo AI"

    var id: String { rawValue }
}

private struct HaloAIMessage: Identifiable, Hashable {
    let id = UUID()
    let role: String
    let text: String
}

private struct HaloMessageThread: Identifiable, Hashable {
    let id: String
    let channel: String
    let name: String
    let unread: Int
}

struct HaloCommsView: View {
    var initialJobID: String? = nil
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var store: JobStore
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [HaloMessage] = []
    @State private var gpsSessions: [HaloGPSSession] = []
    @State private var sharing = Set<String>()
    @State private var lastSent: [String: Date] = [:]
    @State private var selectedJobID: String?
    @State private var selectedThreadChannel: String?
    @State private var selectedThreadName: String?
    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachmentData: Data?
    @State private var pendingAttachmentName: String?
    @State private var pendingAttachmentContentType: String?
    @State private var pendingAttachmentPreview: UIImage?
    @State private var pendingAttachmentCaption: String?
    @State private var showFileImporter = false
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var conversationMode: HaloConversationMode = .office
    @State private var aiMessages: [HaloAIMessage] = [
        HaloAIMessage(
            role: "assistant",
            text: "I’m connected to your live HALO assignments. Ask what to do next, which jobs need proof, or whether a maintenance handoff is waiting."
        )
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    conversationModeControl

                    if conversationMode == .office {
                        if !gpsSessions.isEmpty {
                            liveLocationSection
                        }
                        inboxSection
                    } else {
                        aiSection
                    }

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
                if let route = UserDefaults.standard.dictionary(forKey: "halo.pending.push-route") as? [String: String] {
                    applyPushRoute(route)
                    UserDefaults.standard.removeObject(forKey: "halo.pending.push-route")
                }
                await refresh()

                while !Task.isCancelled {
                    // APNs invalidation is the realtime path. Poll only as a resilience
                    // fallback when push is healthy; use a shorter fallback when it is not.
                    let fallbackSeconds = session.activationInfo?.nativePushDeliveryConfigured == true ? 300.0 : 60.0
                    try? await Task.sleep(for: .seconds(fallbackSeconds))
                    if network.isConnected {
                        await refresh()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .haloOpenComms)) { note in
                guard let route = note.object as? [String: String] else { return }
                applyPushRoute(route)
                UserDefaults.standard.removeObject(forKey: "halo.pending.push-route")
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .haloDataInvalidated)) { _ in
                guard network.isConnected else { return }
                Task { await refresh() }
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
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await loadSelectedPhoto(item) }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                loadImportedFile(result)
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

    private var conversationModeControl: some View {
        HStack(spacing: 6) {
            ForEach(HaloConversationMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        conversationMode = mode
                        selectedThreadChannel = nil
                        selectedThreadName = nil
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode == .ai ? "sparkles" : "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(mode.rawValue)
                            .font(HaloType.body(11, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(conversationMode == mode ? HaloTheme.ink : .white.opacity(0.48))
                    .background(conversationMode == mode ? HaloTheme.lime : Color.white.opacity(0.045))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.035))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.055), lineWidth: 1)
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("HALO AI · GROK")
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(network.isConnected ? HaloTheme.fieldLive : HaloTheme.warning)
                        .frame(width: 6, height: 6)
                    Text(network.isConnected ? "LIVE DATA" : "OFFLINE")
                        .font(HaloType.body(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.38))
                }
            }

            LazyVStack(spacing: 9) {
                ForEach(aiMessages) { item in
                    aiBubble(item)
                        .id(item.id)
                }

                if isSending {
                    HStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(HaloTheme.lime)
                            Text("Halo is checking live operations…")
                                .font(HaloType.body(11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(HaloTheme.fieldCard)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Spacer(minLength: 52)
                    }
                }
            }

            if aiMessages.count <= 1 {
                HStack(spacing: 8) {
                    aiSuggestion("What’s next?")
                    aiSuggestion("Needs photos?")
                    aiSuggestion("Open handoffs?")
                }
            }

            Text("Grounded in your assigned HALO jobs. Halo AI cannot approve spending or silently change job records.")
                .font(HaloType.body(9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private func aiBubble(_ item: HaloAIMessage) -> some View {
        let outgoing = item.role == "user"
        return HStack {
            if outgoing { Spacer(minLength: 52) }

            VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
                if !outgoing {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text("HALO AI")
                            .font(HaloType.body(8, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(HaloTheme.lime)
                }

                Text(item.text)
                    .font(HaloType.body(13, weight: .medium))
                    .foregroundStyle(outgoing ? HaloTheme.ink : .white)
                    .multilineTextAlignment(outgoing ? .trailing : .leading)
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

    private func aiSuggestion(_ text: String) -> some View {
        Button {
            draft = text
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Text(text)
                .font(HaloType.body(9, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

    private var unreadCount: Int {
        messages.filter { $0.from != "field" && !$0.read }.count
    }

    private var propertyThreads: [HaloMessageThread] {
        Dictionary(grouping: messages.filter { $0.channel.hasPrefix("group:") || $0.channel.hasPrefix("dm:crew:") }, by: \.channel)
            .map { channel, rows in
                HaloMessageThread(
                    id: channel,
                    channel: channel,
                    name: rows.compactMap(\.threadName).first ?? (channel.hasPrefix("dm:crew:") ? "Office direct" : "Property Live"),
                    unread: rows.filter { $0.from != "field" && !$0.read }.count
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedMessages: [HaloMessage] {
        let rows: [HaloMessage]
        if let selectedThreadChannel {
            rows = messages.filter { $0.channel == selectedThreadChannel }
        } else {
            rows = messages
        }
        return rows.sorted { ($0.at ?? "") < ($1.at ?? "") }
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("MESSAGES")
                Spacer()
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(HaloType.body(9, weight: .bold))
                        .foregroundStyle(HaloTheme.lime)
                } else if !messages.isEmpty {
                    Text("\(messages.count) recent")
                        .font(HaloType.body(9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }

            if !propertyThreads.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedThreadChannel = nil
                            selectedThreadName = nil
                        } label: {
                            Text("All")
                                .font(HaloType.body(9, weight: .bold))
                                .foregroundStyle(selectedThreadChannel == nil ? HaloTheme.ink : .white.opacity(0.56))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(selectedThreadChannel == nil ? HaloTheme.lime : Color.white.opacity(0.05))
                                .clipShape(Capsule())
                        }

                        ForEach(propertyThreads) { thread in
                            Button {
                                selectedThreadChannel = thread.channel
                                selectedThreadName = thread.name
                                selectedJobID = nil
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 6) {
                                    Text(thread.name)
                                        .lineLimit(1)
                                    if thread.unread > 0 {
                                        Text("\(thread.unread)")
                                            .font(HaloType.body(8, weight: .bold))
                                            .foregroundStyle(selectedThreadChannel == thread.channel ? HaloTheme.ink : .white)
                                            .frame(minWidth: 18, minHeight: 18)
                                            .background(selectedThreadChannel == thread.channel ? Color.black.opacity(0.10) : HaloTheme.actionBlue)
                                            .clipShape(Circle())
                                    }
                                }
                                .font(HaloType.body(9, weight: .bold))
                                .foregroundStyle(selectedThreadChannel == thread.channel ? HaloTheme.ink : .white.opacity(0.62))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(selectedThreadChannel == thread.channel ? HaloTheme.lime : Color.white.opacity(0.05))
                                .clipShape(Capsule())
                            }
                        }
                    }
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
                    ForEach(displayedMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openMessage(message)
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

    private func applyPushRoute(_ route: [String: String]) {
        conversationMode = .office
        let channel = route["channel"] ?? ""
        let unitID = route["unitId"] ?? ""
        if channel.hasPrefix("group:") || channel.hasPrefix("dm:crew:") {
            selectedThreadChannel = channel
            selectedThreadName = channel.hasPrefix("dm:crew:") ? "Office direct" : nil
        } else {
            selectedThreadChannel = nil
            selectedThreadName = nil
        }
        if !unitID.isEmpty {
            selectedJobID = unitID
        }
        if (route["category"] ?? "") == "gps_request" {
            selectedJobID = unitID.isEmpty ? nil : unitID
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openMessage(_ message: HaloMessage) {
        if message.channel.hasPrefix("group:") || message.channel.hasPrefix("dm:crew:") {
            selectedThreadChannel = message.channel
            selectedThreadName = message.threadName ?? (message.channel.hasPrefix("dm:crew:") ? "Office direct" : nil)
        }
        if let unitID = message.unitID {
            selectedJobID = unitID
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard message.from != "field", !message.read, let token = session.activationToken else { return }
        Task {
            try? await HaloAPI.shared.markMessageRead(messageID: message.id, activationToken: token)
            await refresh()
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
            sectionLabel(conversationMode == .ai ? "ASK HALO AI" : "REPLY TO OFFICE")

            Menu {
                if conversationMode == .office {
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
                } else {
                    Button("All assigned jobs") {
                        selectedJobID = nil
                        selectedThreadChannel = nil
                        selectedThreadName = nil
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
                    Image(systemName: conversationMode == .ai ? "scope" : "link")
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

            if conversationMode == .office {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Photo", systemImage: "photo")
                            .font(HaloType.body(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("File", systemImage: "paperclip")
                            .font(HaloType.body(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    if pendingAttachmentPreview != nil {
                        Menu {
                            Button("Job photo") { pendingAttachmentCaption = nil }
                            Button("Before") { pendingAttachmentCaption = "before" }
                            Button("After") { pendingAttachmentCaption = "after" }
                            Button("Flagged") { pendingAttachmentCaption = "flagged" }
                        } label: {
                            Label((pendingAttachmentCaption ?? "Job photo").capitalized, systemImage: "tag")
                                .font(HaloType.body(10, weight: .bold))
                                .foregroundStyle(HaloTheme.lime)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(HaloTheme.lime.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                }

                if pendingAttachmentData != nil {
                    HStack(spacing: 10) {
                        if let preview = pendingAttachmentPreview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: 54, height: 54)
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(HaloTheme.lime)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pendingAttachmentName ?? "Attachment")
                                .font(HaloType.body(11, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(pendingAttachmentPreview == nil ? "Ready to send" : ((pendingAttachmentCaption ?? "job photo").uppercased()))
                                .font(HaloType.body(8, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.40))
                        }

                        Spacer()

                        Button {
                            clearAttachment()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    conversationMode == .ai ? "Ask Halo about today’s work…" : "Message the office…",
                    text: $draft,
                    axis: .vertical
                )
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
                            Image(systemName: conversationMode == .ai ? "sparkles" : "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(canSend ? HaloTheme.lime : Color.white.opacity(0.08))
                    .foregroundStyle(canSend ? HaloTheme.ink : .white.opacity(0.28))
                    .clipShape(Circle())
                }
                .disabled(!canSend || isSending)
                .accessibilityLabel(conversationMode == .ai ? "Ask Halo AI" : "Send message")
            }
        }
    }

    private var canSend: Bool {
        guard network.isConnected else { return false }
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if conversationMode == .ai { return hasText }
        return hasText || pendingAttachmentData != nil
    }

    private var selectedJobLabel: String {
        if conversationMode == .ai {
            guard let selectedJobID, let job = store.jobs.first(where: { $0.id == selectedJobID }) else {
                return "All assigned jobs · Live context"
            }
            return "Focus · Unit \(job.unit) · \(job.propertyName)"
        }

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

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let jpeg = image.jpegData(compressionQuality: 0.88)
            else {
                errorMessage = "That photo could not be loaded."
                return
            }
            guard jpeg.count <= 10 * 1024 * 1024 else {
                errorMessage = "Message attachments must be 10 MB or smaller."
                return
            }
            pendingAttachmentData = jpeg
            pendingAttachmentName = "halo-photo-\(Int(Date().timeIntervalSince1970)).jpg"
            pendingAttachmentContentType = "image/jpeg"
            pendingAttachmentPreview = image
            pendingAttachmentCaption = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadImportedFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 10 * 1024 * 1024 else {
                errorMessage = "Message attachments must be 10 MB or smaller."
                return
            }

            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let allowed = ["application/pdf", "text/csv", "text/plain"]
            guard allowed.contains(type) else {
                errorMessage = "Choose a PDF, CSV, or text file."
                return
            }

            pendingAttachmentData = data
            pendingAttachmentName = url.lastPathComponent
            pendingAttachmentContentType = type
            pendingAttachmentPreview = nil
            pendingAttachmentCaption = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAttachment() {
        selectedPhotoItem = nil
        pendingAttachmentData = nil
        pendingAttachmentName = nil
        pendingAttachmentContentType = nil
        pendingAttachmentPreview = nil
        pendingAttachmentCaption = nil
    }

    private func send() {
        guard canSend, let token = session.activationToken else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = conversationMode
        isSending = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if mode == .ai {
            let history = aiMessages
                .suffix(12)
                .map { HaloGrokTurn(role: $0.role, content: $0.text) }

            aiMessages.append(HaloAIMessage(role: "user", text: text))
            draft = ""

            Task {
                do {
                    let answer = try await HaloAPI.shared.askGrok(
                        message: text,
                        jobID: selectedJobID,
                        history: history,
                        activationToken: token
                    )
                    await MainActor.run {
                        aiMessages.append(HaloAIMessage(role: "assistant", text: answer.reply))
                        isSending = false
                        errorMessage = nil
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } catch {
                    await MainActor.run {
                        aiMessages.append(HaloAIMessage(
                            role: "assistant",
                            text: "I couldn’t reach Halo AI. \(error.localizedDescription)"
                        ))
                        isSending = false
                        errorMessage = error.localizedDescription
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            }
            return
        }

        let jobID = selectedJobID
        let channel = selectedThreadChannel
        let attachmentData = pendingAttachmentData
        let attachmentName = pendingAttachmentName
        let attachmentType = pendingAttachmentContentType
        let attachmentCaption = pendingAttachmentCaption
        let clientID = UUID()

        Task {
            if !network.isConnected {
                await queueMessage(
                    id: clientID,
                    text: text,
                    jobID: jobID,
                    channel: channel,
                    attachmentData: attachmentData,
                    attachmentName: attachmentName,
                    attachmentType: attachmentType,
                    attachmentCaption: attachmentCaption,
                    token: token
                )
                return
            }

            do {
                try await HaloAPI.shared.sendMessage(
                    text: text,
                    jobID: jobID,
                    channel: channel,
                    attachmentData: attachmentData,
                    attachmentName: attachmentName,
                    attachmentContentType: attachmentType,
                    attachmentCaption: attachmentCaption,
                    clientID: clientID,
                    activationToken: token
                )
                await MainActor.run {
                    draft = ""
                    clearAttachment()
                    isSending = false
                }
                await refresh()
            } catch {
                let retryable: Bool
                if case HaloAPIError.transport = error {
                    retryable = true
                } else if case let HaloAPIError.http(status, _) = error {
                    retryable = status >= 500 || status == 408 || status == 429
                } else {
                    retryable = false
                }

                if retryable {
                    await queueMessage(
                        id: clientID,
                        text: text,
                        jobID: jobID,
                        channel: channel,
                        attachmentData: attachmentData,
                        attachmentName: attachmentName,
                        attachmentType: attachmentType,
                        attachmentCaption: attachmentCaption,
                        token: token
                    )
                    return
                }

                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func queueMessage(
        id: UUID,
        text: String,
        jobID: String?,
        channel: String?,
        attachmentData: Data?,
        attachmentName: String?,
        attachmentType: String?,
        attachmentCaption: String?,
        token: String
    ) async {
        do {
            var attachmentPath = ""
            if let attachmentData, !attachmentData.isEmpty {
                let ext = (attachmentName as NSString?)?.pathExtension.isEmpty == false
                    ? (attachmentName as NSString?)?.pathExtension ?? "bin"
                    : (attachmentType == "application/pdf" ? "pdf" : attachmentType?.hasPrefix("image/") == true ? "jpg" : "bin")
                attachmentPath = try await OfflineMediaStore.shared.save(attachmentData, preferredExtension: ext).path
            }

            await MainActor.run {
                var payload: [String: String] = [
                    "text": text,
                    "channel": channel ?? "",
                    "attachmentPath": attachmentPath,
                    "attachmentName": attachmentName ?? "",
                    "attachmentContentType": attachmentType ?? "",
                    "attachmentCaption": attachmentCaption ?? ""
                ]
                payload = payload.filter { !$0.value.isEmpty }
                OfflineQueue.shared.enqueue(
                    id: id,
                    jobID: jobID ?? "",
                    kind: .messageSend,
                    payload: payload,
                    activationToken: token,
                    context: modelContext
                )
                draft = ""
                clearAttachment()
                isSending = false
                errorMessage = "Queued securely · this message will send when HALO reconnects."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            await MainActor.run {
                isSending = false
                errorMessage = "HALO could not secure this offline message. \(error.localizedDescription)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

}
