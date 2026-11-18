import ConnectionCore
import Domain
import Darwin
import Foundation
import Infrastructure

public struct SSHHostKeyCandidate: Identifiable, Sendable {
    public let algorithm: String
    public let fingerprint: String
    fileprivate let key: String
    public var id: String { fingerprint }
}

public struct SSHHostTrustReview: Sendable {
    public let host: SSHHost
    public let savedFingerprints: String
    public let candidates: [SSHHostKeyCandidate]
    fileprivate let original: Data
    fileprivate let secondary: Data?
    fileprivate let knownHosts: URL
}

/// 扫描只提供待核对的公钥；只有用户确认的那把公钥会被写入信任库。
public enum SSHHostTrust {
    public static func inspect(_ host: SSHHost, home: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> SSHHostTrustReview {
        try OpenSSHArguments.validate(host)
        guard host.jump.isEmpty else {
            throw MacTermError("此主机使用跳板机，请通过受信任的跳板机路径核对指纹；此处不进行直连扫描。")
        }
        let file = home.appendingPathComponent(".ssh/known_hosts")
        guard let original = try readFile(file) else {
            throw MacTermError("尚无已保存的指纹，请在首次连接时核对并确认服务器身份。")
        }
        let secondary = try readFile(home.appendingPathComponent(".ssh/known_hosts2"))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = folder.appendingPathComponent("saved")
        try original.write(to: saved)
        let lookup = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-F", target(host), "-f", saved.path])
        guard lookup.status == 0 else { throw MacTermError("没有找到此地址和端口的已保存指纹。") }
        // 验证能安全更新，拒绝吊销、CA 和通配符规则。
        _ = try replacingTarget(in: original, lookup: lookup.text, target: target(host), replacement: "")
        if let secondary {
            let other = folder.appendingPathComponent("secondary")
            try secondary.write(to: other)
            let match = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-F", target(host), "-f", other.path])
            guard match.status == 1 else {
                throw MacTermError("known_hosts2 也包含此目标或无法检查，请先由管理员核对两份信任记录。")
            }
        }
        let fingerprints = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-lf", "-", "-E", "sha256"], input: lookup.output)
        guard fingerprints.status == 0 else { throw MacTermError("无法读取已保存的指纹。") }
        let scan = try await ProcessRunner.run("/usr/bin/ssh-keyscan", ["-T", "5", "-p", String(host.port), "-t", "ed25519,ecdsa,rsa", host.address])
        guard scan.status == 0 else { throw MacTermError("无法获取服务器公钥，请检查网络和 SSH 端口。") }
        var candidates: [SSHHostKeyCandidate] = []
        for line in scan.text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 3,
                  ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "ssh-rsa"].contains(String(fields[1])),
                  Data(base64Encoded: String(fields[2])) != nil else { continue }
            let key = "\(fields[1]) \(fields[2])"
            let result = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-lf", "-", "-E", "sha256"], input: Data((key + "\n").utf8))
            let values = result.text.split(whereSeparator: { $0.isWhitespace })
            guard result.status == 0, values.count >= 2, values[1].hasPrefix("SHA256:") else { continue }
            let candidate = SSHHostKeyCandidate(algorithm: String(fields[1]), fingerprint: String(values[1]), key: key)
            if !candidates.contains(where: { $0.id == candidate.id }) { candidates.append(candidate) }
        }
        guard !candidates.isEmpty else { throw MacTermError("服务器未返回可核对的公钥。") }
        return SSHHostTrustReview(host: host, savedFingerprints: fingerprints.text, candidates: candidates,
                                  original: original, secondary: secondary, knownHosts: file)
    }

    public static func update(_ review: SSHHostTrustReview, fingerprint: String) async throws {
        guard let candidate = review.candidates.first(where: { $0.fingerprint == fingerprint }) else {
            throw MacTermError("请选择已展示并核对的指纹。")
        }
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = folder.appendingPathComponent("saved")
        try review.original.write(to: saved)
        let lookup = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-F", target(review.host), "-f", saved.path])
        guard lookup.status == 0 else { throw MacTermError("无法定位原有指纹。") }
        let replacement = target(review.host) + " " + candidate.key + "\n"
        let updated = try replacingTarget(in: review.original, lookup: lookup.text,
                                         target: target(review.host), replacement: replacement)
        // 展示后信任库若有变化，要求重新检查，避免覆盖其他工具的新修改。
        guard try readFile(review.knownHosts) == review.original,
              try readFile(review.knownHosts.deletingLastPathComponent().appendingPathComponent("known_hosts2")) == review.secondary else {
            throw MacTermError("信任记录已变化，请关闭窗口后重新检查。")
        }
        try updated.write(to: review.knownHosts, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: review.knownHosts.path)
    }

    static func target(_ host: SSHHost) -> String {
        host.port == 22 ? host.address : "[\(host.address)]:\(host.port)"
    }

    /// ssh-keygen -F 负责匹配散列主机名；只修改其报告的行，保留共享行中的其他别名。
    static func replacingTarget(in original: Data, lookup: String, target: String, replacement: String) throws -> Data {
        guard let text = String(data: original, encoding: .utf8) else { throw MacTermError("信任记录不是 UTF-8 文本。") }
        let pattern = try NSRegularExpression(pattern: #"(?m)^# Host .* found: line ([0-9]+)(?:[ \t]+(?:CA|REVOKED))?[ \t]*\r?$"#)
        let matches = pattern.matches(in: lookup, range: NSRange(lookup.startIndex..., in: lookup))
        let indices = Set(matches.compactMap { match -> Int? in
            guard let range = Range(match.range(at: 1), in: lookup), let number = Int(lookup[range]) else { return nil }
            return number - 1
        })
        var lines = text.components(separatedBy: "\n")
        guard !indices.isEmpty, indices.allSatisfy({ lines.indices.contains($0) }) else {
            throw MacTermError("无法安全定位待更新的指纹。")
        }
        for index in indices {
            let fields = lines[index].split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 3, !fields[0].hasPrefix("@"),
                  !fields[0].contains("*"), !fields[0].contains("?"), !fields[0].contains("!") else {
                throw MacTermError("此目标使用吊销、CA 或通配符规则，请由管理员更新。")
            }
            if fields[0].hasPrefix("|1|") {
                lines[index] = ""
            } else {
                let names = fields[0].split(separator: ",")
                let remaining = names.filter { String($0).caseInsensitiveCompare(target) != .orderedSame }
                guard remaining.count < names.count else { throw MacTermError("此记录需要由管理员核对后更新。") }
                lines[index] = remaining.isEmpty ? "" : remaining.joined(separator: ",") + " " + fields.dropFirst().joined(separator: " ")
            }
        }
        var output = lines.joined(separator: "\n")
        if !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
        output += replacement
        return Data(output.utf8)
    }

    private static func readFile(_ file: URL) throws -> Data? {
        let manager = FileManager.default
        // attributesOfItem 使用 lstat，拒绝符号链接及其他用户拥有的信任文件。
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: file.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 4 * 1024 * 1024 else {
            throw MacTermError("信任记录的类型、所有者或大小不符合安全要求。")
        }
        return try Data(contentsOf: file)
    }

    private static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return folder
    }
}
