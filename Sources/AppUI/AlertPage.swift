import AlertCore
import Domain
import MonitorCore
import SwiftUI

struct AlertPage: View {
    let host: SSHHost
    @State private var running = false
    @State private var limit = 85.0
    @State private var duration = 15.0
    @State private var events: [Event] = []
    @State private var error = ""

    struct Event: Identifiable {
        let id = UUID()
        let time: Date
        let message: String
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(host.label).font(.title2)
                Spacer()
                Toggle("内存告警", isOn: $running).toggleStyle(.switch)
            }
            Slider(value: $limit, in: 1...100, step: 1) { Text("内存阈值 \(Int(limit))%") }.disabled(running)
            Slider(value: $duration, in: 0...120, step: 5) { Text("持续 \(Int(duration)) 秒") }.disabled(running)
            if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
            List(events) { event in
                HStack { Text(event.message); Spacer(); Text(event.time.formatted()) }
            }
        }.task(id: running) { if running { await poll() } }
    }

    private func poll() async {
        var threshold = Threshold()
        let engine = MonitorEngine()
        while !Task.isCancelled {
            do {
                let sample = try await engine.sample(host)
                try Task.checkCancellation()
                error = ""
                if let memory = sample.usedMemory,
                   let event = threshold.update(memory, limit: limit / 100, duration: duration, at: sample.time) {
                    events.insert(Event(time: sample.time, message: "内存告警\(event.rawValue)"), at: 0)
                    if events.count > 200 { events.removeLast() }
                }
            } catch is CancellationError { return }
            catch { self.error = error.localizedDescription; threshold = Threshold() }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }
}
