import ConnectionCore
import Domain
import Foundation
import MonitorCore
import StorageCore
import SSHAskPassCore
import XCTest
@testable import SFTPCore

final class CoreTests: XCTestCase {
    func testConnectionSecurity() throws {
        let host = SSHHost(address: "example.invalid", user: "ops", jump: "ops@jump.invalid:2222")
        let batch = try OpenSSHArguments.common(host, interactive: false)
        XCTAssertTrue(batch.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(batch.contains("BatchMode=yes"))
        XCTAssertTrue(try OpenSSHArguments.common(host, interactive: true).contains("StrictHostKeyChecking=ask"))
        XCTAssertThrowsError(try OpenSSHArguments.validate(SSHHost(address: "-oProxyCommand=bad", user: "ops")))
        XCTAssertEqual(OpenSSHArguments.shellQuote("a'b"), "'a'\\''b'")
    }

    func testKeychainAskPassIsExplicitAndOneTime() throws {
        let hostID = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let token = folder.appendingPathComponent("token")
        try Data(hostID.uuidString.utf8).write(to: token)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: token.path)
        let secret = Data("test-secret".utf8)
        let result = try SSHAskPassHandler.credential(for: "ops@example's password:", tokenURL: token) { id in
            XCTAssertEqual(id, hostID)
            return secret
        }
        XCTAssertEqual(result, secret)
        XCTAssertFalse(FileManager.default.fileExists(atPath: token.path))
    }

    func testKeychainAskPassLeavesOtherPromptsForUser() throws {
        let hostID = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let token = folder.appendingPathComponent("token")
        try Data(hostID.uuidString.utf8).write(to: token)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: token.path)
        let result = try SSHAskPassHandler.credential(for: "Enter passphrase for key:", tokenURL: token) { _ in
            XCTFail("A server password must not be sent as a local private-key passphrase")
            return nil
        }
        XCTAssertNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: token.path))
        let challenge = try SSHAskPassHandler.credential(for: "Password:", tokenURL: token) { _ in
            XCTFail("Generic challenge text can represent a one-time code")
            return nil
        }
        XCTAssertNil(challenge)
    }

    func testOldHostConfigurationDefaultsToManualAuthentication() throws {
        let identifier = UUID()
        let data = Data("""
        {"id":"\(identifier.uuidString)","name":"legacy","address":"host.example","user":"ops","port":22,"identity":"","jump":""}
        """.utf8)
        let decoded = try JSONDecoder().decode(SSHHost.self, from: data)
        XCTAssertFalse(decoded.keychainAuthenticationEnabled)
    }

    func testConfigurationBackupPreservesTunnelsAndReadsOlderFiles() throws {
        let host = SSHHost(name: "legacy", address: "host.example", user: "ops")
        let hostData = try JSONEncoder().encode(host)
        let hostJSON = String(decoding: hostData, as: UTF8.self)
        let legacy = Data("{\"version\":1,\"hosts\":[\(hostJSON)],\"fontSize\":13}".utf8)
        let oldBackup = try JSONDecoder().decode(AppConfigurationBackup.self, from: legacy)
        XCTAssertTrue(oldBackup.tunnels.isEmpty)

        let tunnel = SSHTunnelProfile(hostID: host.id, name: "web", mode: .local, listenPort: 18080)
        let current = AppConfigurationBackup(hosts: [host], tunnels: [tunnel], fontSize: 13)
        let roundTrip = try JSONDecoder().decode(AppConfigurationBackup.self, from: JSONEncoder().encode(current))
        XCTAssertEqual(roundTrip.hosts, [host])
        XCTAssertEqual(roundTrip.tunnels, [tunnel])
    }

    func testSFTPPathBoundary() throws {
        XCTAssertEqual(try SFTPClient.path("/测试 文件"), "\"/测试 文件\"")
        XCTAssertThrowsError(try SFTPClient.path("/x\nrm /"))
        XCTAssertThrowsError(try SFTPClient.path("/tmp/*"))
        XCTAssertThrowsError(try SFTPClient.path("-r"))
    }

    func testStoreMigrationAndCRUD() async throws {
        let store = try Store()
        let host = SSHHost(name: "Example", address: "example.invalid", user: "ops")
        let empty = try await store.hosts()
        XCTAssertTrue(empty.isEmpty)
        let tunnel = SSHTunnelProfile(hostID: host.id, name: "Web", mode: .local,
                                      listenPort: 18080, destination: "127.0.0.1", destinationPort: 8080)
        try await store.saveConfiguration(hosts: [host], tunnels: [tunnel])
        let savedTunnels = try await store.tunnels(hostID: host.id)
        XCTAssertEqual(savedTunnels, [tunnel])
        let saved = try await store.hosts()
        XCTAssertEqual(saved, [host])
        try await store.delete(host.id)
        let remainingTunnels = try await store.tunnels(hostID: host.id)
        XCTAssertTrue(remainingTunnels.isEmpty)
        let deleted = try await store.hosts()
        XCTAssertTrue(deleted.isEmpty)
    }

    func testSampleDeltasAndMemory() throws {
        let before = try Sample.parse(fixture(cpu: "100 0 100 800 0 0 0 0", rx: 100, tx: 200),
                                      time: Date(timeIntervalSince1970: 1))
        let after = try Sample.parse(fixture(cpu: "130 0 120 850 0 0 0 0", rx: 160, tx: 220),
                                     time: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(after.usedMemory, 0.75)
        XCTAssertEqual(after.utilization(since: before), 0.5)
        let cpu = try XCTUnwrap(after.cpuBreakdown(since: before))
        XCTAssertEqual(cpu.user, 0.3, accuracy: 0.0001)
        XCTAssertEqual(cpu.system, 0.2, accuracy: 0.0001)
        XCTAssertEqual(cpu.idle, 0.5, accuracy: 0.0001)
        XCTAssertEqual(cpu.ioWait, 0, accuracy: 0.0001)
        XCTAssertEqual(after.rates(since: before, interface: "eth0")?.receive, 30)
        XCTAssertEqual(after.rates(since: before, interface: "eth0")?.transmit, 10)
        XCTAssertNil(before.utilization(since: after))
        XCTAssertThrowsError(try Sample.parse("invalid"))
    }

    private func fixture(cpu: String, rx: Int, tx: Int) -> String {
        ["cpu \(cpu)", "MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 250 kB",
         "eth0: \(rx) 0 0 0 0 0 0 0 \(tx) 0 0 0 0 0 0 0", "0.1 0.2 0.3 1/2 1", "/dev/vda /"]
            .joined(separator: "\n__MACTERM__\n")
    }
}
