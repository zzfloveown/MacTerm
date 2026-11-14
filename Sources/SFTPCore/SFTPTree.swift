import Domain
import Foundation

extension SFTPClient {
    /// 不跟随符号链接。普通文件使用相对路径，目录按父目录优先排列。
    public func directoryTree(_ root: String, on host: SSHHost) async throws -> (directories: [String], files: [String]) {
        var directories = [""]
        var files: [String] = []
        var offset = 0
        while offset < directories.count {
            if offset >= 10_000 { throw MacTermError("目录超过递归扫描上限。") }
            let folder = directories[offset]
            offset += 1
            let source = folder.isEmpty ? root : root + "/" + folder
            for entry in try await entries(source, on: host) {
                let subpath = folder.isEmpty ? entry.name : folder + "/" + entry.name
                switch entry.permissions.map({ $0 & 0o170000 }) {
                case 0o040000: directories.append(subpath)
                case 0o100000: files.append(subpath)
                default: continue
                }
                guard files.count + directories.count <= 100_000 else {
                    throw MacTermError("目录超过递归扫描上限。")
                }
            }
        }
        return (directories, files)
    }
}
