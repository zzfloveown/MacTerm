import Domain
import SwiftUI
import UserNotifications

struct AlertPage: View {
    let host: SSHHost
    @ObservedObject var monitor: HostMonitor
    @State private var rules = MonitorAlertRule.defaults
    @State private var error = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(host.label).font(.title2)
                Spacer()
                Button("启用 macOS 通知") {
                    Task {
                        do {
                            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            error = allowed ? "" : "请在系统设置中允许 MacTerm 通知。"
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Button("保存规则") {
                    Task {
                        do {
                            try await monitor.store.save(rules, for: host.id)
                            monitor.setRules(rules)
                            if rules.contains(where: \.enabled) { monitor.start(host, interval: 5) }
                            error = ""
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(!loaded || rules.contains { !$0.limit.isFinite || !$0.duration.isFinite
                    || !(0...$0.metric.maximum).contains($0.limit) || !(0...3600).contains($0.duration) })
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if !monitor.status.isEmpty { Text(monitor.status).foregroundStyle(.red) }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("指标").gridColumnAlignment(.leading)
                    Text("阈值")
                    Text("持续秒数")
                }.foregroundStyle(.secondary)
                ForEach($rules) { $rule in
                    GridRow {
                        Toggle(rule.metric.rawValue, isOn: $rule.enabled)
                        HStack {
                            TextField("阈值", value: $rule.limit, format: .number)
                                .disabled(rule.metric == .disconnected).frame(width: 95)
                            Text(rule.metric.unit).foregroundStyle(.secondary)
                        }
                        TextField("秒数", value: $rule.duration, format: .number).frame(width: 95)
                    }
                }
            }.disabled(!loaded)
            List(monitor.events) { event in
                HStack { Text(event.message); Spacer(); Text(event.date.formatted()) }
            }
        }.task {
            do {
                rules = try await monitor.store.alertRules(for: host.id)
                try await monitor.loadAlerts(for: host.id)
                loaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
