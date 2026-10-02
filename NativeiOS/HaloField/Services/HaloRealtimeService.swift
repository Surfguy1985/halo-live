import Foundation

@MainActor
final class HaloRealtimeService: ObservableObject {
    enum ConnectionState: Equatable {
        case stopped
        case connecting
        case connected
        case reconnecting
        case expired

        var label: String {
            switch self {
            case .stopped: "OFF"
            case .connecting: "CONNECTING"
            case .connected: "LIVE"
            case .reconnecting: "RECONNECTING"
            case .expired: "SESSION EXPIRED"
            }
        }
    }

    @Published private(set) var state: ConnectionState = .stopped
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var lastError: String?

    private let host = "halo-back-office-copy-1d779ace.base44.app"
    private let appID = "6aa4569d140d940e1d779ace"
    private let actorName = "HaloNative"
    private let actorRoom = "native-field-v1"
    private let api = HaloAPI.shared

    private var activationToken: String?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var generation = UUID()
    private var lastHealthReportAt = Date.distantPast

    func start(activationToken token: String?) {
        let clean = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clean.isEmpty else {
            stop()
            return
        }

        if activationToken == clean,
           state == .connected || state == .connecting || state == .reconnecting {
            return
        }

        stopSocket(clearToken: false)
        activationToken = clean
        reconnectAttempt = 0
        connect()
    }

    func stop() {
        activationToken = nil
        reconnectAttempt = 0
        stopSocket(clearToken: false)
        state = .stopped
        lastError = nil
    }

    func requestRefresh() {
        guard state == .connected else { return }
        send(["type": "refresh"])
    }

    private func connect() {
        guard let activationToken, !activationToken.isEmpty else {
            state = .stopped
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        let connectionGeneration = UUID()
        generation = connectionGeneration

        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = "/parties/\(actorName)/\(actorRoom)"
        components.queryItems = [
            URLQueryItem(name: "_pk", value: UUID().uuidString.lowercased()),
            URLQueryItem(name: "app_id", value: appID),
            URLQueryItem(name: "handler", value: actorName)
        ]

        guard let url = components.url else {
            lastError = "HALO realtime URL could not be created."
            state = .reconnecting
            scheduleReconnect()
            return
        }

        state = reconnectAttempt == 0 ? .connecting : .reconnecting
        lastError = nil

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task, generation: connectionGeneration)
        }

        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, self.generation == connectionGeneration else { return }
                if self.state == .connected {
                    self.send(["type": "ping"])
                }
            }
        }

        // URLSession queues a send once the WebSocket task has resumed. The actor
        // also sends a hello immediately; sending here makes authentication fast
        // even if that first server frame is delayed.
        sendAuth(activationToken)
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation expectedGeneration: UUID) async {
        do {
            while !Task.isCancelled, generation == expectedGeneration {
                let frame = try await task.receive()
                let data: Data
                switch frame {
                case .string(let text):
                    data = Data(text.utf8)
                case .data(let bytes):
                    data = bytes
                @unknown default:
                    continue
                }
                handle(data)
            }
        } catch {
            guard !Task.isCancelled, generation == expectedGeneration else { return }
            lastError = error.localizedDescription
            state = .reconnecting
            if let activationToken, Date().timeIntervalSince(lastHealthReportAt) >= 300 {
                lastHealthReportAt = Date()
                Task { await api.reportHealth(category: "realtime", message: "Realtime connection dropped: \(error.localizedDescription)", source: "HaloRealtimeService", activationToken: activationToken) }
            }
            scheduleReconnect()
        }
    }

    private func handle(_ data: Data) {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = raw["type"] as? String
        else { return }

        switch type {
        case "hello":
            if let token = activationToken {
                sendAuth(token)
            }

        case "authenticated":
            reconnectAttempt = 0
            state = .connected
            lastError = nil
            lastEventAt = Date()
            NotificationCenter.default.post(
                name: .haloDataInvalidated,
                object: ["source": "websocket", "scopes": ["jobs", "messages", "live"]]
            )

        case "invalidate":
            let scopes = raw["scopes"] as? [String] ?? ["jobs", "messages", "live"]
            lastEventAt = Date()
            NotificationCenter.default.post(
                name: .haloDataInvalidated,
                object: ["source": "websocket", "scopes": scopes]
            )

        case "session_expired":
            state = .expired
            lastError = "This device activation expired. Activate HALO again."
            if let activationToken {
                Task { await api.reportHealth(category: "realtime", message: "Native realtime session expired.", severity: "high", source: "HaloRealtimeService", activationToken: activationToken) }
            }
            stopSocket(clearToken: false)

        case "error":
            lastError = raw["message"] as? String ?? "HALO realtime is temporarily unavailable."

        case "pong":
            break

        default:
            break
        }
    }

    private func sendAuth(_ token: String) {
        send([
            "type": "auth",
            "activationToken": token
        ])
    }

    private func send(_ payload: [String: String]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }

        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self else { return }
                self.lastError = error.localizedDescription
                if self.state != .expired {
                    self.state = .reconnecting
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard activationToken != nil, state != .expired else { return }
        guard reconnectTask == nil else { return }

        reconnectAttempt += 1
        let pollingFallback = reconnectAttempt >= 3
        let delay = pollingFallback
            ? 60.0
            : min(pow(1.7, Double(max(0, reconnectAttempt - 1))), 15.0)

        // A flaky WebSocket must never make the field app unusable. After three
        // consecutive failures, expose the service as stopped so RootView uses its
        // 15-second HTTP refresh path, then quietly retry realtime later.
        if pollingFallback {
            state = .stopped
            lastError = "Live socket unavailable — HALO is using resilient polling."
        }

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.activationToken != nil, self.state != .expired else { return }
                self.reconnectTask = nil
                self.stopSocket(clearToken: false, cancelReconnect: false)
                self.connect()
            }
        }
    }

    private func stopSocket(clearToken: Bool, cancelReconnect: Bool = true) {
        if cancelReconnect {
            reconnectTask?.cancel()
            reconnectTask = nil
        }
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        generation = UUID()
        if clearToken {
            activationToken = nil
        }
    }
}
