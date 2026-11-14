import Combine
import Domain
import Foundation
import SFTPCore
import StorageCore

/// 跨窗口共享队列。每个目标串行传输，每次最多执行三项任务。
@MainActor
public final class TransferQueue: ObservableObject {
    @Published public private(set) var records: [TransferRecord] = []
    @Published public private(set) var progress: [UUID: TransferProgress] = [:]
    @Published public private(set) var failure = ""

    private let store: Store
    private let client = SFTPClient()
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var stopStates: [UUID: String] = [:]
    private var loaded = false
    private var loading: Task<Void, Never>?

    public init(store: Store) { self.store = store }

    public func load() async {
        guard !loaded else { return }
        if let loading { await loading.value; return }
        let operation = Task { await restore() }
        loading = operation
        await operation.value
        loading = nil
    }

    private func restore() async {
        do {
            records = try await store.transfers()
            for item in records where item.state == "进行中" || item.state == "待传输" {
                try await update(item.id, state: "已暂停")
            }
            loaded = true
        } catch {
            failure = error.localizedDescription
            loaded = false
        }
    }

    public func enqueue(_ job: TransferJob) async throws {
        try await enqueue([job])
    }

    public func enqueue(_ jobs: [TransferJob]) async throws {
        await load()
        guard loaded else { throw MacTermError("无法读取传输队列。") }
        let entries = jobs.map { TransferRecord(name: $0.local.lastPathComponent, state: "待传输", job: $0) }
        try await store.save(entries)
        records.insert(contentsOf: entries.reversed(), at: 0)
        startPending()
    }

    public func pause(_ id: UUID) async { await stop(id, state: "已暂停") }
    public func cancel(_ id: UUID) async { await stop(id, state: "已取消") }

    public func resume(_ id: UUID) async {
        guard tasks[id] == nil, let item = records.first(where: { $0.id == id }),
              ["已暂停", "失败"].contains(item.state), item.job != nil else { return }
        guard stopStates[id] == nil else { return }
        stopStates[id] = "待传输"
        defer { stopStates[id] = nil; startPending() }
        do { try await update(id, state: "待传输") }
        catch { failure = error.localizedDescription }
    }

    private func stop(_ id: UUID, state: String) async {
        if let task = tasks[id] {
            stopStates[id] = state
            task.cancel()
        } else if stopStates[id] == nil,
                  records.contains(where: { $0.id == id && ["待传输", "已暂停"].contains($0.state) }) {
            stopStates[id] = state
            defer { stopStates[id] = nil; startPending() }
            do { try await update(id, state: state) } catch { failure = error.localizedDescription }
        }
    }

    private func startPending() {
        let pending = records.reversed().filter { $0.state == "待传输" && tasks[$0.id] == nil && stopStates[$0.id] == nil }
        for item in pending where tasks.count < 3 {
            guard let job = item.job, !conflicts(with: job) else { continue }
            let id = item.id
            tasks[id] = Task { await run(id, job: job) }
        }
    }

    private func conflicts(with job: TransferJob) -> Bool {
        records.contains { item in
            guard tasks[item.id] != nil, let active = item.job else { return false }
            let sameLocal = active.local.standardizedFileURL == job.local.standardizedFileURL
            let sameRemote = active.host.address == job.host.address && active.host.port == job.host.port
                && active.remote == job.remote
            return sameLocal || sameRemote
        }
    }

    private func run(_ id: UUID, job: TransferJob) async {
        defer {
            tasks[id] = nil
            stopStates[id] = nil
            progress[id] = nil
            startPending()
        }
        do {
            try await update(id, state: "进行中")
            try Task.checkCancellation()
            let reporter = ProgressReporter()
            try await client.transfer(local: job.local, remote: job.remote, on: job.host, upload: job.upload, id: id) { value in
                guard reporter.shouldReport(value) else { return }
                Task { @MainActor [weak self] in
                    if self?.tasks[id] != nil { self?.progress[id] = value }
                }
            }
            try await update(id, state: "已完成")
        } catch {
            let state = stopStates[id] ?? "失败"
            do { try await update(id, state: state, detail: state == "失败" ? error.localizedDescription : nil) }
            catch { failure = error.localizedDescription }
        }
    }

    private func update(_ id: UUID, state: String, detail: String? = nil) async throws {
        guard var item = records.first(where: { $0.id == id }) else { return }
        item.state = state
        item.detail = detail
        try await store.save(item)
        if let index = records.firstIndex(where: { $0.id == id }) { records[index] = item }
    }
}

private final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    private var initial = true

    func shouldReport(_ progress: TransferProgress) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ContinuousClock.now
        guard initial || last.duration(to: now) >= .milliseconds(200) || progress.completed == progress.total else { return false }
        initial = false
        last = now
        return true
    }
}
