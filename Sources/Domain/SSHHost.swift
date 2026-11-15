import Foundation

public struct SSHHost: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var user: String
    public var port: Int
    public var identity: String
    public var jump: String
    public var group: String?
    /// 只有用户显式允许时，终端才会从 Keychain 自动提交一次服务器密码。
    public var keychainAuthenticationEnabled: Bool

    public init(id: UUID = UUID(), name: String = "", address: String = "", user: String = "",
                port: Int = 22, identity: String = "", jump: String = "", group: String? = nil,
                keychainAuthenticationEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.user = user
        self.port = port
        self.identity = identity
        self.jump = jump
        self.group = group
        self.keychainAuthenticationEnabled = keychainAuthenticationEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, address, user, port, identity, jump, group, keychainAuthenticationEnabled
    }

    /// 兼容增加 Keychain 选项前已保存的主机配置。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        address = try values.decode(String.self, forKey: .address)
        user = try values.decode(String.self, forKey: .user)
        port = try values.decode(Int.self, forKey: .port)
        identity = try values.decode(String.self, forKey: .identity)
        jump = try values.decode(String.self, forKey: .jump)
        group = try values.decodeIfPresent(String.self, forKey: .group)
        keychainAuthenticationEnabled = try values.decodeIfPresent(Bool.self, forKey: .keychainAuthenticationEnabled) ?? false
    }

    public var label: String { name.isEmpty ? address : name }
}

public struct MacTermError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum SSHTunnelMode: String, CaseIterable, Codable, Hashable, Sendable {
    case local = "本地转发"
    case remote = "远程转发"
    case dynamic = "SOCKS5"
}

/// 可持久化的 SSH 隧道配置，不包含凭据或连接状态。
public struct SSHTunnelProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var hostID: UUID
    public var name: String
    public var mode: SSHTunnelMode
    public var listenPort: Int
    public var destination: String
    public var destinationPort: Int
    public var reconnect: Bool

    public init(id: UUID = UUID(), hostID: UUID, name: String, mode: SSHTunnelMode,
                listenPort: Int, destination: String = "127.0.0.1", destinationPort: Int = 80,
                reconnect: Bool = false) {
        self.id = id
        self.hostID = hostID
        self.name = name
        self.mode = mode
        self.listenPort = listenPort
        self.destination = destination
        self.destinationPort = destinationPort
        self.reconnect = reconnect
    }
}

/// 不包含密码或私钥内容的可移植应用配置备份。
public struct AppConfigurationBackup: Codable, Sendable {
    public var version: Int
    public let hosts: [SSHHost]
    public let tunnels: [SSHTunnelProfile]
    public let fontSize: Double

    private enum CodingKeys: String, CodingKey { case version, hosts, tunnels, fontSize }

    public init(version: Int = 1, hosts: [SSHHost], tunnels: [SSHTunnelProfile] = [], fontSize: Double) {
        self.version = version
        self.hosts = hosts
        self.tunnels = tunnels
        self.fontSize = fontSize
    }

    /// 旧版备份没有隧道字段，导入时作为空配置兼容。
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        hosts = try values.decode([SSHHost].self, forKey: .hosts)
        tunnels = try values.decodeIfPresent([SSHTunnelProfile].self, forKey: .tunnels) ?? []
        fontSize = try values.decode(Double.self, forKey: .fontSize)
    }
}
