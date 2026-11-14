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

    public init(id: UUID = UUID(), name: String = "", address: String = "", user: String = "",
                port: Int = 22, identity: String = "", jump: String = "", group: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.user = user
        self.port = port
        self.identity = identity
        self.jump = jump
        self.group = group
    }

    public var label: String { name.isEmpty ? address : name }
}

public struct MacTermError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
