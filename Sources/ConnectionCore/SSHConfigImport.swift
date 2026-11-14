import Domain
import Foundation

public struct SSHConfigImport: Sendable {
    public let hosts: [SSHHost]
    public let skipped: Int

    /// 只读取显式 Host 段和可安全映射的字段。配置内容不会交给 OpenSSH 求值。
    public static func parse(_ text: String, currentUser: String, home: URL) -> SSHConfigImport {
        var blocks: [(aliases: [String], options: [String: String])] = []
        var index: Int?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = tokenize(line)
            guard let keyword = parts.first?.lowercased() else { continue }
            if keyword == "host" {
                blocks.append((Array(parts.dropFirst()), [:]))
                index = blocks.indices.last
            } else if keyword == "match" {
                index = nil
            } else if let index, parts.count == 2, blocks[index].options[keyword] == nil {
                blocks[index].options[keyword] = parts[1]
            }
        }
        var result: [SSHHost] = []
        var seen: Set<String> = []
        var skipped = 0
        for (aliases, options) in blocks {
            for alias in aliases {
                guard !alias.contains(where: { "*?!".contains($0) }), !seen.contains(alias.lowercased()),
                      let port = Int(options["port"] ?? "22"),
                      !(options["proxycommand"].map { $0 != "none" } ?? false) else {
                    skipped += 1
                    continue
                }
                let identity = options["identityfile"] ?? ""
                let resolved = identity.hasPrefix("~/")
                    ? home.appendingPathComponent(String(identity.dropFirst(2))).path : identity
                let jump = options["proxyjump"] ?? ""
                let host = SSHHost(name: alias, address: options["hostname"] ?? alias,
                                   user: options["user"] ?? currentUser, port: port,
                                   identity: resolved == "none" ? "" : resolved, jump: jump == "none" ? "" : jump)
                guard (try? OpenSSHArguments.validate(host)) != nil else { skipped += 1; continue }
                seen.insert(alias.lowercased())
                result.append(host)
            }
        }
        return SSHConfigImport(hosts: result, skipped: skipped)
    }

    private static func tokenize(_ line: Substring) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var escaped = false
        for character in line {
            if escaped {
                field.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted && character == "#" {
                break
            } else if !quoted && (character.isWhitespace || (character == "=" && fields.isEmpty)) {
                if !field.isEmpty { fields.append(field); field = "" }
            } else {
                field.append(character)
            }
        }
        guard !quoted, !escaped else { return [] }
        if !field.isEmpty { fields.append(field) }
        return fields
    }
}
