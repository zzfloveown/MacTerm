// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MacTerm",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacTerm", targets: ["MacTermApp"]),
        .executable(name: "SSHAskPass", targets: ["SSHAskPass"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.19.0")
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Infrastructure"),
        .target(name: "StorageCore", dependencies: ["Domain", "Infrastructure", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "ConnectionCore", dependencies: ["Domain"]),
        .target(name: "SSHCore", dependencies: ["Domain", "ConnectionCore", "Infrastructure"]),
        .target(name: "SSHAskPassCore"),
        .executableTarget(name: "SSHAskPass", dependencies: ["SSHAskPassCore"]),
        .target(name: "SFTPCore", dependencies: ["Domain", "ConnectionCore", "Infrastructure"]),
        .target(name: "TerminalCore", dependencies: ["Domain", "ConnectionCore", "SSHCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .target(name: "MonitorCore", dependencies: ["Domain", "SSHCore"]),
        .target(name: "TransferCore", dependencies: ["Domain", "SFTPCore", "StorageCore"]),
        .target(name: "AlertCore", dependencies: ["MonitorCore"]),
        .target(name: "DockerCore", dependencies: ["Domain", "SSHCore"]),
        .target(name: "KubernetesCore", dependencies: ["Infrastructure"]),
        .target(name: "AppUI", dependencies: ["Domain", "ConnectionCore", "StorageCore", "SSHCore", "TerminalCore", "SFTPCore", "MonitorCore", "TransferCore", "AlertCore", "DockerCore", "KubernetesCore"]),
        .executableTarget(name: "MacTermApp", dependencies: ["AppUI", "StorageCore", "TransferCore"]),
        .testTarget(name: "MacTermTests", dependencies: ["Domain", "Infrastructure", "ConnectionCore", "SSHCore", "SSHAskPassCore", "SFTPCore", "MonitorCore", "StorageCore"])
    ],
    swiftLanguageModes: [.v5]
)
