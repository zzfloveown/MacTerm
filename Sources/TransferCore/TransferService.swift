import Domain
import Foundation
import SFTPCore
import StorageCore

public struct TransferService: Sendable {
    let client: SFTPClient
    let store: Store

    public init(store: Store, client: SFTPClient = SFTPClient()) {
        self.store = store
        self.client = client
    }

    /// 先保存传输记录，再执行网络操作并写入终态。
    public func copy(local: URL, remote: String, upload: Bool, host: Host) async throws {
        var record = TransferRecord(name: local.lastPathComponent, state: "进行中")
        try await store.save(record)
        do {
            if upload {
                try await client.upload(local: local.path, remote: remote, on: host)
            } else {
                try await client.download(remote: remote, local: local.path, on: host)
            }
        } catch {
            record.state = error is CancellationError ? "已取消" : "失败"
            try await store.save(record)
            throw error
        }
        record.state = "已完成"
        try await store.save(record)
    }
}
