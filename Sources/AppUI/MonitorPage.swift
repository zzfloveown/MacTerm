import Charts
import Combine
import Domain
import Foundation
import MonitorCore
import SwiftUI
import UniformTypeIdentifiers

struct MonitorPage: View {
    let host: SSHHost
    @ObservedObject var monitor: HostMonitor
    @State private var history: [MonitorPoint] = []
    @State private var interval = 5
    @State private var period = 1800
    @State private var status = ""
    @State private var exporting = false

    private var sample: Sample? { monitor.sample }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(host.label).font(.title2)
                    Spacer()
                    Picker("刷新间隔", selection: $interval) {
                        ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) 秒").tag($0) }
                    }.fixedSize().disabled(monitor.running)
                    Button(monitor.running ? "停止监控" : "启动监控") {
                        if monitor.running { monitor.stop() } else { monitor.start(host, interval: interval) }
                    }
                }
                if !monitor.status.isEmpty { Text(monitor.status).foregroundStyle(.red) }
                if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                HStack {
                    metric("CPU", percentage(monitor.latest?.cpu))
                    metric("内存", percentage(sample?.usedMemory))
                    metric("Swap", percentage(sample?.usedSwap))
                    metric("负载", sample?.load ?? "—")
                }
                HStack {
                    Picker("历史范围", selection: $period) {
                        Text("30 分钟").tag(1800)
                        Text("1 小时").tag(3600)
                        Text("24 小时").tag(86_400)
                    }.pickerStyle(.segmented)
                    Button("导出 CSV") { exporting = true }.disabled(history.isEmpty)
                }
                Chart(chartPoints) { point in
                    if let cpu = point.cpu {
                        LineMark(x: .value("时间", point.time), y: .value("使用率", cpu))
                            .foregroundStyle(by: .value("指标", "CPU"))
                    }
                    if let memory = point.memory {
                        LineMark(x: .value("时间", point.id), y: .value("使用率", memory))
                            .foregroundStyle(by: .value("指标", "内存"))
                    }
                }.chartYScale(domain: 0...1).frame(height: 160)
                output("磁盘分区", sample?.volumes.joined(separator: "\n") ?? "")
                output("磁盘 I/O", diskRates)
                Chart(chartPoints) { point in
                    if let incoming = point.incoming {
                        LineMark(x: .value("时间", point.time), y: .value("B/s", incoming))
                            .foregroundStyle(by: .value("方向", "下载"))
                    }
                    if let outgoing = point.outgoing {
                        LineMark(x: .value("时间", point.time), y: .value("B/s", outgoing))
                            .foregroundStyle(by: .value("方向", "上传"))
                    }
                }.frame(height: 130)
                output("网卡与 TCP", sample?.interfaces ?? "")
                output("系统信息", sample?.system ?? "")
                output("温度", sample?.temperature.isEmpty == false ? sample?.temperature ?? "" : "不可用")
                output("处理器与内存明细", resourceDetails)
                LinuxProcessList(host: host, engine: monitor.engine)
            }
        }.task(id: period) { await loadHistory() }
            .onReceive(monitor.$latest.compactMap { $0 }) { point in
                let start = Date().addingTimeInterval(-Double(period))
                history.removeAll { $0.time < start || $0.time == point.time }
                history.append(point)
            }
            .fileExporter(isPresented: $exporting, document: MonitorCSV(text: MonitorPoint.csv(history)),
                          contentType: .commaSeparatedText, defaultFilename: "MacTerm-monitor.csv") {
                if case .failure(let error) = $0 { status = error.localizedDescription }
            }
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

    private var chartPoints: [MonitorPoint] {
        let strideSize = max(1, (history.count + 599) / 600)
        return stride(from: 0, to: history.count, by: strideSize).map { history[$0] }
    }

    private var diskRates: String {
        guard let sample, let previous = monitor.previous else { return "" }
        return sample.disks.keys.sorted().compactMap { disk in
            guard let rate = sample.diskRates(since: previous, disk: disk) else { return nil }
            return "\(disk)  读取 \(rate.read.formatted(.number.precision(.fractionLength(0)))) B/s  写入 \(rate.write.formatted(.number.precision(.fractionLength(0)))) B/s"
        }.joined(separator: "\n")
    }

    private var resourceDetails: String {
        guard let sample else { return "" }
        let cores = sample.cpu.keys.filter { $0 != "cpu" }.sorted()
        let cpu = cores.map { core in
            "\(core): " + percentage(monitor.previous.flatMap { sample.utilization(since: $0, core: core) })
        }.joined(separator: "    ")
        let breakdown = monitor.previous.flatMap { sample.cpuBreakdown(since: $0) }
        let cpuDetail = breakdown.map {
            "用户态 \(percentage($0.user))  系统态 \(percentage($0.system))  空闲 \(percentage($0.idle))  I/O Wait \(percentage($0.ioWait))"
        } ?? "CPU 分项等待下一次采样"
        let memory = ["MemTotal", "MemAvailable", "MemFree", "Buffers", "Cached", "SwapTotal", "SwapFree"]
            .compactMap { key in sample.memory[key].map { "\(key): \($0) KiB" } }.joined(separator: "    ")
        return "\(cores.count) 个逻辑核心\n\(cpuDetail)\n\(cpu)\n\(memory)"
    }

    private func loadHistory() async {
        do {
            let points = try await monitor.store.monitorPoints(for: host.id, since: Date().addingTimeInterval(-Double(period)))
            if !Task.isCancelled { history = points }
        } catch { status = error.localizedDescription }
    }
}

private struct MonitorCSV: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
