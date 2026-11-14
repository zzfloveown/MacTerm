import ConnectionCore
import Foundation
import XCTest

final class SSHConfigTests: XCTestCase {
    func testImportExplicitProfiles() throws {
        let config = """
            Include dangerous.conf
            Host *
                User default
            Host staging backup
                HostName=example.invalid
                User ops
                Port 2222
                IdentityFile "~/with spaces"
                ProxyJump ops@jump.invalid
            Match exec "whoami"
                HostName ignored.invalid
            Host unsafe
                ProxyCommand arbitrary
            Host staging
                Port 999
            """
        let result = SSHConfigImport.parse(config, currentUser: "runner", home: URL(fileURLWithPath: "/Users/runner"))
        XCTAssertEqual(result.hosts.map(\.label), ["staging", "backup"])
        XCTAssertEqual(result.hosts.map(\.address), ["example.invalid", "example.invalid"])
        XCTAssertEqual(result.hosts.first?.port, 2222)
        XCTAssertEqual(result.hosts.first?.identity, "/Users/runner/with spaces")
        XCTAssertEqual(result.skipped, 3)

        let host = try XCTUnwrap(result.hosts.first)
        let interactive = try OpenSSHArguments.common(host, interactive: true)
        let background = try OpenSSHArguments.common(host, interactive: false)
        XCTAssertTrue(interactive.contains("ControlMaster=auto"))
        XCTAssertTrue(background.contains("ControlMaster=no"))
        XCTAssertEqual(interactive.first { $0.hasPrefix("ControlPath=") },
                       background.first { $0.hasPrefix("ControlPath=") })
    }
}
