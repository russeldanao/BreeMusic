import Combine
import Foundation

enum BreeStreamConnection: Equatable, Sendable {
    case wifi
    case cellular
    case constrained
    case unknown
}

enum BreeStreamQuality: String, CaseIterable, Identifiable {
    case automatic
    case dataSaver
    case standard
    case high
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .dataSaver: "Data Saver · 64 kbps"
        case .standard: "Standard · 128 kbps"
        case .high: "High · 320 kbps"
        case .original: "Original quality"
        }
    }

    func bitRate(for connection: BreeStreamConnection) -> Int {
        switch self {
        case .automatic:
            switch connection {
            case .cellular, .constrained: 96
            case .wifi: 160
            case .unknown: 128
            }
        case .dataSaver: 64
        case .standard: 128
        case .high: 320
        case .original: 0
        }
    }
}

#if os(iOS)
import Network

@MainActor
final class BreeNetworkPathMonitor: ObservableObject {
    @Published private(set) var connection: BreeStreamConnection = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "BreeMusic.NetworkPath")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connection: BreeStreamConnection
            if path.isConstrained || path.isExpensive {
                connection = .constrained
            } else if path.usesInterfaceType(.cellular) {
                connection = .cellular
            } else if path.usesInterfaceType(.wifi) {
                connection = .wifi
            } else {
                connection = .unknown
            }
            Task { @MainActor [weak self] in self?.connection = connection }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
#endif
