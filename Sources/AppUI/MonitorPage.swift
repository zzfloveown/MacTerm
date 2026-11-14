import Charts
import Domain
import Foundation
import MonitorCore
import SwiftUI

struct MonitorPage: View {
    let host: SSHHost
    @State private var sample: Sample?
    @State private var cpu: Double?
    @State private var network: [String] = []
    @State private var history: [Point] = []
    @State private var interval = 5
    @State private var running = false
    @State private var status = ""
    @State private var processes = ""
    private let engine = MonitorEngine()

    struct Point: Identifiable {
        var id: Date
        var cpu: Double
        var memory: Double?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(host.label).font(.title2)
                    Spacer()
                    Picker("刷新间隔", selection: $interval) {
                        ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) 秒").tag($0) }
                    }.fixedSize()
                    Button(running ? "停止监控" : "启动监控") { running.toggle() }
                }
                if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                HStack {
                    metric("CPU", percentage(cpu))
                    metric("内存", percentage(sample?.usedMemory))
                    metric("Swap", percentage(sample?.usedSwap))
                    metric("负载", sample?.load ?? "—")
                }
                Chart(history) { point in
                    LineMark(x: .value("时间", point.id), y: .value("使用率", point.cpu))
                        .foregroundStyle(by: .value("指标", "CPU"))
                    if let memory = point.memory {
                        LineMark(x: .value("时间", point.id), y: .value("使用率", memory))
                            .foregroundStyle(by: .value("指标", "内存"))
                    }
                }.chartYScale(domain: 0...1).frame(height: 160)
                output("磁盘分区", sample?.volumes.joined(separator: "\n") ?? "")
                output("网络 I/O", network.joined(separator: "\n"))
                HStack {
                    Text("进程").font(.headline)
                    Button("刷新进程") {
                        Task {
                            do { processes = try await engine.processes(host) }
                            catch { status = error.localizedDescription }
                        }
                    }
                }
                Text(processes).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }.task(id: "\(running)-\(interval)") { if running { await poll() } }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        GroupBox(title) {
            Text(value).font(.title3.monospacedDigit()).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func output(_ title: String, _ text: String) -> some View {
        GroupBox(title) {
            Text(text.isEmpty ? "—" : text).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func percentage(_ value: Double?) -> String { value?.formatted(.percent.precision(.fractionLength(1))) ?? "—" }

    private func poll() async {
        var previous: Sample?
        while !Task.isCancelled {
            do {
                let next = try await engine.sample(host)
                try Task.checkCancellation()
                sample = next
                status = ""
                if let previous {
                    cpu = next.utilization(since: previous)
                    if let cpu { history.append(Point(id: next.time, cpu: cpu, memory: next.usedMemory)) }
                    if history.count > 300 { history.removeFirst(history.count - 300) }
                    network = next.network.keys.sorted().compactMap { name in
                        guard let speed = next.rates(since: previous, interface: name) else { return nil }
                        return "\(name)    ↓ \(speed.receive.formatted(.number.precision(.fractionLength(0)))) B/s    ↑ \(speed.transmit.formatted(.number.precision(.fractionLength(0)))) B/s"
                    }
                }
                previous = next
            } catch is CancellationError { return }
            catch { status = error.localizedDescription; previous = nil; cpu = nil; network = [] }
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        }
    }
}
