import AppUI
import OSLog
import StorageCore
import SwiftUI
import TransferCore

@main
struct MacTermApp: App {
    private let setup = Result {
        let folder = try Store.applicationSupport()
        let store = try Store(url: folder.appendingPathComponent("MacTerm.sqlite"))
        return (store, TransferQueue(store: store), MonitorRegistry(store: store))
    }

    var body: some Scene {
        WindowGroup("MacTerm") {
            switch setup {
            case .success(let (store, transfers, monitors)):
                Workspace(store: store, transfers: transfers, monitors: monitors)
                    .frame(minWidth: 850, minHeight: 540)
            case .failure:
                ContentUnavailableView("无法打开数据库", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text("请检查应用数据目录的权限和磁盘可用空间。"))
            }
        }
        .defaultSize(width: 1180, height: 780)
    }
}
