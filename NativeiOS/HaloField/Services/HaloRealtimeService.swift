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
    private var fallbackTask: Task<Void, Never>?
    private var fallbackCursor: HaloRealtimeCursorSnapshot?
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
           socket != nil || fallbackTask != nil {
            return
        }

        stopSocket(clearToken: false)
        stopFallback()
        activationToken = clean
        reconnectAttempt = 0
        fallbackCursor = nil
        connect()
    }

    func stop() {
        activationToken = nil
        reconnectAttempt = 0
        stopSocket(clearToken: false)
        stopFallback()
        state = .stopped
        lastError = nil
    }

    func requestRefresh() {
        if state == .connected, socket != nil {
            send(["type": "refresh"])
        } else {
            Task { [weak self] in
                await self?.pollFallbackOnce()
            }
        }
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
            beginFallbackPolling()
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
                if self.socket === task, self.state == .connected {
                    self.send(["type": "ping"])
                }
            }
        }

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
            handleSocketFailure(error)
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
            fallbackCursor = nil
            stopFallback()
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
                Task {
                    await api.reportHealth(
                        category: "realtime",
                        message: "Native realtime session expired.",
                        severity: "high",
                        source: "HaloRealtimeService",
                        activationToken: activationToken
                    )
                }
            }
            stopSocket(clearToken: false)
            stopFallback()

        case "error":
            lastError = raw["message"] as? String ?? "HALO realtime is temporarily unavailable."

        case "pong":
            lastEventAt = Date()

        default:
            break
        }
    }

    private func handleSocketFailure(_ error: Error) {
        lastError = error.localizedDescription
        state = .reconnecting

        if let activationToken, Date().timeIntervalSince(lastHealthReportAt) >= 300 {
            lastHealthReportAt = Date()
            Task {
                await api.reportHealth(
                    category: "realtime",
                    message: "Realtime connection dropped: \(error.localizedDescription)",
                    source: "HaloRealtimeService",
                    activationToken: activationToken
                )
            }
        }

        scheduleReconnect()
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
                guard let self, self.state != .expired else { return }
                self.handleSocketFailure(error)
            }
        }
    }

    private func scheduleReconnect() {
        guard activationToken != nil, state != .expired else { return }
        guard reconnectTask == nil else { return }

        reconnectAttempt += 1
        let shouldFallback = reconnectAttempt >= 2
        let delay = shouldFallback
            ? 60.0
            : min(pow(1.7, Double(max(0, reconnectAttempt - 1))), 8.0)

        if shouldFallback {
            beginFallbackPolling()
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

    private func beginFallbackPolling() {
        guard fallbackTask == nil,
              let activationToken,
              !activationToken.isEmpty,
              state != .expired else { return }

        fallbackTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollFallbackOnce()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func pollFallbackOnce() async {
        guard let activationToken, !activationToken.isEmpty, state != .expired else { return }

        do {
            let next = try await api.fetchRealtimeCursor(activationToken: activationToken)
            let previous = fallbackCursor
            fallbackCursor = next
            lastEventAt = Date()
            state = .connected
            lastError = nil

            guard let previous else {
                NotificationCenter.default.post(
                    name: .haloDataInvalidated,
                    object: ["source": "cursor_poll", "scopes": ["jobs", "messages", "live"]]
                )
                return
            }

            var scopes: [String] = []
            if previous.jobs != next.jobs { scopes.append("jobs") }
            if previous.messages != next.messages { scopes.append("messages") }
            if previous.live != next.live { scopes.append("live") }

            if !scopes.isEmpty {
                NotificationCenter.default.post(
                    name: .haloDataInvalidated,
                    object: ["source": "cursor_poll", "scopes": scopes]
                )
            }
        } catch let error as HaloAPIError {
            if case let .http(status, _) = error, status == 401 || status == 403 {
                state = .expired
                lastError = "This device activation expired. Activate HALO again."
                stopFallback()
                stopSocket(clearToken: false)
                return
            }
            if socket == nil {
                state = .reconnecting
                lastError = "Live sync is reconnecting…"
            }
        } catch {
            if socket == nil {
                state = .reconnecting
                lastError = "Live sync is reconnecting…"
            }
        }
    }

    private func stopFallback() {
        fallbackTask?.cancel()
        fallbackTask = nil
        fallbackCursor = nil
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
