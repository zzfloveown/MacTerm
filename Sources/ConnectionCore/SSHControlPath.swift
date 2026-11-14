import CryptoKit
import Darwin
import Domain
import Foundation

enum SSHControlPath {
    // mkdtemp 原子创建仅当前用户可访问的短目录，避免 Unix 套接字长度限制。
    private static let directory: String? = {
        var template = Array("/tmp/macterm.XXXXXXXX".utf8CString)
        return template.withUnsafeMutableBufferPointer { buffer in
            guard let address = buffer.baseAddress, mkdtemp(address) != nil else { return nil }
            return String(cString: address)
        }
    }()

    static func forHost(_ host: SSHHost) -> String? {
        guard let directory else { return nil }
        let parts = [host.id.uuidString, host.address, host.user, String(host.port), host.identity, host.jump]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8))
        return directory + "/" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
