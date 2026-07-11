import SwiftUI
import Darwin

// MARK: - 실시간 모니터 (메뉴바 + 플로팅 창)

struct TopProcess: Identifiable {
    let id = UUID()
    let name: String
    let cpu: Double
}

enum MonitorMath {
    // Kernel counters can reset or wrap. Treat that interval as unavailable instead
    // of using wrapping subtraction, which would create a near-UInt64.max delta.
    static func counterDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    static func bytesPerSecond(delta: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        let rate = Double(delta) / elapsed
        guard rate.isFinite, rate >= 0 else { return 0 }
        return min(rate, 1_000_000_000_000)
    }

    static func displayBytes(_ value: Double) -> Int64 {
        guard value.isFinite, value > 0 else { return 0 }
        return Int64(min(value, 1_000_000_000_000))
    }
}

/// 시스템 지표 원시값 수집 (델타 계산은 MonitorModel이 담당)
enum MonitorSampler {
    struct RawSample {
        var cpuUsed: UInt64 = 0
        var cpuTotal: UInt64 = 0
        var memUsed: Int64 = 0
        var memTotal: Int64 = 0
        var diskFree: Int64 = 0
        var netRx: UInt64 = 0
        var netTx: UInt64 = 0
        var top: [TopProcess] = []
    }

    static func sample() -> RawSample {
        var raw = RawSample()

        // CPU 누적 틱
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if cpuResult == KERN_SUCCESS {
            let user = UInt64(cpuInfo.cpu_ticks.0)
            let system = UInt64(cpuInfo.cpu_ticks.1)
            let idle = UInt64(cpuInfo.cpu_ticks.2)
            let nice = UInt64(cpuInfo.cpu_ticks.3)
            raw.cpuUsed = user + system + nice
            raw.cpuTotal = user + system + nice + idle
        }

        // 메모리
        raw.memTotal = Int64(ProcessInfo.processInfo.physicalMemory)
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let vmResult = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let pageSize = Int64(vm_kernel_page_size)
            raw.memUsed = (Int64(vmStats.active_count) + Int64(vmStats.wire_count)
                + Int64(vmStats.compressor_page_count)) * pageSize
        }

        // 디스크 여유 공간
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
        ]) {
            raw.diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        // 네트워크 누적 바이트 (en*: 이더넷/Wi-Fi)
        var addrsPtr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addrsPtr) == 0 {
            defer { freeifaddrs(addrsPtr) }
            var cursor = addrsPtr
            while let ifa = cursor {
                if let addr = ifa.pointee.ifa_addr,
                   addr.pointee.sa_family == UInt8(AF_LINK),
                   let data = ifa.pointee.ifa_data {
                    let name = String(cString: ifa.pointee.ifa_name)
                    if name.hasPrefix("en") {
                        let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                        raw.netRx &+= UInt64(ifData.ifi_ibytes)
                        raw.netTx &+= UInt64(ifData.ifi_obytes)
                    }
                }
                cursor = ifa.pointee.ifa_next
            }
        }

        // CPU 상위 프로세스
        let psOutput = Shell.run("/bin/ps", ["-A", "-c", "-r", "-o", "pcpu=,comm="]).output
        raw.top = psOutput.split(separator: "\n").prefix(5).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let spaceIndex = trimmed.firstIndex(of: " "),
                  let cpu = Double(trimmed[..<spaceIndex]) else { return nil }
            let name = trimmed[trimmed.index(after: spaceIndex)...]
                .trimmingCharacters(in: .whitespaces)
            return TopProcess(name: name, cpu: cpu)
        }

        return raw
    }
}

@MainActor
final class MonitorModel: ObservableObject {
    static let shared = MonitorModel()

    @Published var cpu: Double = 0
    @Published var memUsed: Int64 = 0
    @Published var memTotal: Int64 = 1
    @Published var diskFree: Int64 = 0
    @Published var downPerSec: Double = 0
    @Published var upPerSec: Double = 0
    @Published var top: [TopProcess] = []

    var memRatio: Double { Double(memUsed) / Double(max(memTotal, 1)) }

    private var timer: Timer?
    private var lastCPU: (used: UInt64, total: UInt64)?
    private var lastNet: (rx: UInt64, tx: UInt64)?
    private var lastNetDate: Date?
    private var isSampling = false

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        Task {
            defer { isSampling = false }
            let raw = await Task.detached(priority: .utility) { MonitorSampler.sample() }.value
            apply(raw)
        }
    }

    private func apply(_ raw: MonitorSampler.RawSample) {
        if let last = lastCPU {
            let usedDelta = Double(MonitorMath.counterDelta(current: raw.cpuUsed, previous: last.used))
            let totalDelta = Double(MonitorMath.counterDelta(current: raw.cpuTotal, previous: last.total))
            if totalDelta > 0 { cpu = min(max(usedDelta / totalDelta * 100, 0), 100) }
        }
        lastCPU = (raw.cpuUsed, raw.cpuTotal)

        let now = Date()
        if let lastNet, let lastNetDate {
            let seconds = now.timeIntervalSince(lastNetDate)
            let received = MonitorMath.counterDelta(current: raw.netRx, previous: lastNet.rx)
            let sent = MonitorMath.counterDelta(current: raw.netTx, previous: lastNet.tx)
            downPerSec = MonitorMath.bytesPerSecond(delta: received, elapsed: seconds)
            upPerSec = MonitorMath.bytesPerSecond(delta: sent, elapsed: seconds)
        }
        lastNet = (raw.netRx, raw.netTx)
        lastNetDate = now

        memUsed = raw.memUsed
        memTotal = raw.memTotal
        diskFree = raw.diskFree
        top = raw.top
    }
}

// MARK: - 공용 모니터 콘텐츠 (플로팅 창 + 메뉴바 공유)

struct MonitorContent: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            barRow(
                name: "프로세서 점유",
                value: model.cpu / 100,
                text: String(format: "%.0f%%", model.cpu)
            )
            barRow(
                name: "메모리 사용 현황",
                value: model.memRatio,
                text: formatBytes(model.memUsed)
            )

            divider

            HStack {
                Text("디스크 가용 용량")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(TossColor.grey700)
                Spacer()
                Text(formatBytes(model.diskFree))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TossColor.mint)
            }

            HStack {
                Text("네트워크")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(TossColor.grey700)
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(formatBytes(MonitorMath.displayBytes(model.downPerSec)))/s")
                    }
                    .foregroundStyle(TossColor.mint)
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(formatBytes(MonitorMath.displayBytes(model.upPerSec)))/s")
                    }
                    .foregroundStyle(TossColor.blue)
                }
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
            }

            divider

            VStack(alignment: .leading, spacing: 8) {
                Text("가장 무거운 점유 앱")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(TossColor.grey400)
                    .kerning(0.5)
                ForEach(model.top) { process in
                    HStack {
                        Text(process.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TossColor.grey700)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpu))
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(TossColor.blue)
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(TossColor.grey100)
            .frame(height: 1)
    }

    private func barRow(name: String, value: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(name)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(TossColor.grey700)
                Spacer()
                Text(text)
                    .font(.system(size: 12.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(TossColor.blue)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TossColor.grey100)
                    Capsule()
                        .fill(TossColor.blue)
                        .frame(width: max(geo.size.width * min(max(value, 0), 1), 6))
                        .animation(.easeOut(duration: 0.8), value: value)
                }
            }
            .frame(height: 9)
        }
    }
}

// MARK: - 플로팅 모니터 창

struct MonitorPanelView: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac 실시간 상태")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TossColor.grey900)
                Spacer()
                Circle()
                    .fill(TossColor.mint)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Rectangle()
                .fill(TossColor.grey100)
                .frame(height: 1)

            MonitorContent(model: model)
                .padding(20)
        }
        .frame(width: 300)
        .background(TossColor.card)
        .onAppear { model.start() }
    }
}

// MARK: - 메뉴바

struct MenuBarLabel: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        Text("\(Int(model.cpu))% ∙ \(Int(model.memRatio * 100))%")
            .monospacedDigit()
            .onAppear { model.start() }
    }
}

struct MenuBarView: View {
    @ObservedObject var model: MonitorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac 실시간 상태")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TossColor.grey900)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            Rectangle()
                .fill(TossColor.grey100)
                .frame(height: 1)

            MonitorContent(model: model)
                .padding(18)

            Rectangle()
                .fill(TossColor.grey100)
                .frame(height: 1)

            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("메인 창 열기", systemImage: "macwindow")
                }
                .buttonStyle(TossButtonStyle())
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
                    .buttonStyle(TossPillButtonStyle(
                        foreground: TossColor.grey700, background: TossColor.grey100
                    ))
            }
            .padding(14)
            .background(TossColor.grey50)
        }
        .frame(width: 300)
        .background(TossColor.card)
    }
}
