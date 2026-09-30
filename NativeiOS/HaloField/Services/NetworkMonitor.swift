import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true
    @Published private(set) var interfaceName = "Network"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.archangel.halofield.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                if path.usesInterfaceType(.wifi) {
                    self.interfaceName = "Wi-Fi"
                } else if path.usesInterfaceType(.cellular) {
                    self.interfaceName = "Cellular"
                } else {
                    self.interfaceName = self.isConnected ? "Network" : "Offline"
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
