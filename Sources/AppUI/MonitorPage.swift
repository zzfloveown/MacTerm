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
    private var cpuBreakdown: (user: Double, system: Double, idle: Double, ioWait: Double)? {
        guard let sample, let previous = monitor.previous else { return nil }
        return sample.cpuBreakdown(since: previous)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.label).font(.title2.weight(.semibold))
                        Text("\(host.user)@\(host.address):\(host.port)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("刷新间隔", selection: $interval) {
                        ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) 秒").tag($0) }
                    }.fixedSize().disabled(monitor.running)
                    Button(monitor.running ? "停止监控" : "启动监控",
                           systemImage: monitor.running ? "stop.fill" : "play.fill") {
                        if monitor.running { monitor.stop() } else { monitor.start(host, interval: interval) }
                    }.buttonStyle(.borderedProminent)
                }
                if !monitor.status.isEmpty { Text(monitor.status).foregroundStyle(.red) }
                if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                HStack(spacing: 12) {
                    metric("CPU", percentage(monitor.latest?.cpu), progress: monitor.latest?.cpu,
                           subtitle: cpuBreakdown.map { "用户 \(percentage($0.user)) · 系统 \(percentage($0.system)) · IO \(percentage($0.ioWait))" })
                    metric("内存", percentage(sample?.usedMemory), progress: sample?.usedMemory,
                           subtitle: memorySubtitle)
                    metric("Swap", percentage(sample?.usedSwap), progress: sample?.usedSwap,
                           subtitle: swapSubtitle)
                    metric("负载", sample?.load ?? "—", progress: nil,
                           subtitle: sample.map { "\($0.cpu.keys.filter { $0 != "cpu" }.count) 个逻辑核心" })
                }
                HStack {
                    Picker("历史范围", selection: $period) {
                        Text("30 分钟").tag(1800)
                        Text("1 小时").tag(3600)
                        Text("24 小时").tag(86_400)
                    }.pickerStyle(.segmented)
                    Button("导出 CSV", systemImage: "square.and.arrow.up") { exporting = true }.disabled(history.isEmpty)
                }
                GroupBox("CPU 与内存趋势") {
                    Chart(chartPoints) { point in
                        if let cpu = point.cpu {
                            LineMark(x: .value("时间", point.time), y: .value("使用率", cpu))
                                .foregroundStyle(by: .value("指标", "CPU"))
                        }
                        if let memory = point.memory {
                            LineMark(x: .value("时间", point.time), y: .value("使用率", memory))
                                .foregroundStyle(by: .value("指标", "内存"))
                        }
                    }.chartYScale(domain: 0...1).frame(height: 160)
                }
                GroupBox("网络吞吐趋势") {
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
                }
                if !parsedVolumes.isEmpty {
                    GroupBox("磁盘分区使用率") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(parsedVolumes) { volume in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(volume.mount).font(.callout.monospaced().weight(.medium))
                                        Text("(\(volume.filesystem) · \(volume.type))")
                                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(volume.usedText) / \(volume.sizeText) (\(percentage(volume.ratio)))")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: min(max(volume.ratio, 0), 1), total: 1)
                                        .tint(volume.ratio > 0.85 ? .red : (volume.ratio > 0.7 ? .orange : .blue))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    output("磁盘分区", sample?.volumes.joined(separator: "\n") ?? "")
                }
                output("磁盘 I/O", diskRates)
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

    private func metric(_ title: String, _ value: String, progress: Double?, subtitle: String?) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                Text(value).font(.title3.bold().monospacedDigit()).frame(maxWidth: .infinity, alignment: .leading)
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1), total: 1)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var memorySubtitle: String? {
        guard let sample, let total = sample.memory["MemTotal"], let available = sample.memory["MemAvailable"],
              total >= available else { return nil }
        let usedBytes = Int64(clamping: (total - available) * 1024)
        let totalBytes = Int64(clamping: total * 1024)
        return "\(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .memory))"
    }

    private var swapSubtitle: String? {
        guard let sample, let total = sample.memory["SwapTotal"], let free = sample.memory["SwapFree"],
              total >= free else { return nil }
        if total == 0 { return "未启用 Swap" }
        let usedBytes = Int64(clamping: (total - free) * 1024)
        let totalBytes = Int64(clamping: total * 1024)
        return "\(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .memory))"
    }

    private struct VolumeRow: Identifiable {
        var id: String { mount + ":" + filesystem }
        let filesystem: String
        let type: String
        let sizeText: String
        let usedText: String
        let ratio: Double
        let mount: String
    }

    private var parsedVolumes: [VolumeRow] {
        guard let lines = sample?.volumes.dropFirst() else { return [] }
        return lines.compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 7, fields[5].hasSuffix("%"),
                  let percent = Double(fields[5].dropLast()),
                  let blocks = Int64(fields[2]), let used = Int64(fields[3]) else { return nil }
            let mount = fields.dropFirst(6).joined(separator: " ")
            return VolumeRow(
                filesystem: String(fields[0]),
                type: String(fields[1]),
                sizeText: ByteCountFormatter.string(fromByteCount: blocks * 1024, countStyle: .file),
                usedText: ByteCountFormatter.string(fromByteCount: used * 1024, countStyle: .file),
                ratio: percent / 100,
                mount: mount
            )
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
            let readStr = ByteCountFormatter.string(fromByteCount: Int64(max(0, rate.read)), countStyle: .file)
            let writeStr = ByteCountFormatter.string(fromByteCount: Int64(max(0, rate.write)), countStyle: .file)
            return "\(disk)  读取 \(readStr)/s  写入 \(writeStr)/s"
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
