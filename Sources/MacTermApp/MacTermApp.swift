import AppUI
import OSLog
import StorageCore
import SwiftUI

@main
struct MacTermApp: App {
    private let store = Result {
        let folder = try Store.applicationSupport()
        return try Store(url: folder.appendingPathComponent("MacTerm.sqlite"))
    }

    var body: some Scene {
        WindowGroup("MacTerm") {
            switch store {
            case .success(let store):
                Workspace(store: store)
                    .frame(minWidth: 850, minHeight: 540)
            case .failure:
                ContentUnavailableView("无法打开数据库", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text("请检查应用数据目录的权限和磁盘可用空间。"))
            }
        }
        .defaultSize(width: 1180, height: 780)
    }
}
