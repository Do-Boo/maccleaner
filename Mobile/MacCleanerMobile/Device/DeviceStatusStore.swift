import Foundation
import Network
import Observation
import UIKit

@MainActor
@Observable
final class DeviceStatusStore {
    private(set) var totalBytes: Int64 = 0
    private(set) var freeBytes: Int64 = 0
    private(set) var batteryLevel: Float = -1
    private(set) var batteryState = UIDevice.BatteryState.unknown
    private(set) var networkLabel = "확인 중"
    private(set) var isNetworkAvailable = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.doyoukim.maccleaner.network")

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        startNetworkMonitoring()
    }

    var usedBytes: Int64 { max(totalBytes - freeBytes, 0) }

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    var batteryText: String {
        guard batteryLevel >= 0 else { return "시뮬레이터" }
        return "\(Int(batteryLevel * 100))%"
    }

    var batteryStateText: String {
        switch batteryState {
        case .charging: "충전 중"
        case .full: "충전 완료"
        case .unplugged: "배터리 사용 중"
        default: "상태 확인 불가"
        }
    }

    func refresh() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        if let values = try? home.resourceValues(forKeys: keys) {
            totalBytes = Int64(values.volumeTotalCapacity ?? 0)
            freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let label: String
            if path.status != .satisfied {
                label = "연결 없음"
            } else if path.usesInterfaceType(.wifi) {
                label = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                label = "셀룰러"
            } else if path.usesInterfaceType(.wiredEthernet) {
                label = "유선 네트워크"
            } else {
                label = "네트워크 연결됨"
            }

            Task { @MainActor in
                self?.networkLabel = label
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
