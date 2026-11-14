import ConnectionCore
import Domain
import Foundation
import MonitorCore
import StorageCore
import XCTest
@testable import SFTPCore

final class CoreTests: XCTestCase {
    func testConnectionSecurity() throws {
        let host = Host(address: "example.invalid", user: "ops", jump: "ops@jump.invalid:2222")
        let batch = try OpenSSHArguments.common(host, interactive: false)
        XCTAssertTrue(batch.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(batch.contains("BatchMode=yes"))
        XCTAssertTrue(try OpenSSHArguments.common(host, interactive: true).contains("StrictHostKeyChecking=ask"))
        XCTAssertThrowsError(try OpenSSHArguments.validate(Host(address: "-oProxyCommand=bad", user: "ops")))
        XCTAssertEqual(OpenSSHArguments.shellQuote("a'b"), "'a'\\''b'")
    }

    func testSFTPPathBoundary() throws {
        XCTAssertEqual(try SFTPClient.path("/测试 文件"), "\"/测试 文件\"")
        XCTAssertThrowsError(try SFTPClient.path("/x\nrm /"))
        XCTAssertThrowsError(try SFTPClient.path("/tmp/*"))
        XCTAssertThrowsError(try SFTPClient.path("-r"))
    }

    func testStoreMigrationAndCRUD() async throws {
        let store = try Store()
        let host = Host(name: "Example", address: "example.invalid", user: "ops")
        let empty = try await store.hosts()
        XCTAssertTrue(empty.isEmpty)
        try await store.save(host)
        let saved = try await store.hosts()
        XCTAssertEqual(saved, [host])
        try await store.delete(host.id)
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
