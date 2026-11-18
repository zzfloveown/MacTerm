import Domain
import Foundation
import Infrastructure
import XCTest
@testable import SSHCore

final class SSHHostTrustTests: XCTestCase {
    func testReplacementPreservesOtherHostsAliasesAndPorts() throws {
        let original = Data("""
        # user comment
        example.invalid,alias.invalid ssh-ed25519 OLD
        [example.invalid]:2222 ssh-ed25519 OTHER_PORT
        unrelated.invalid ssh-ed25519 UNRELATED
        example.invalid ssh-rsa OLD_RSA

        """.utf8)
        let lookup = "# Host example.invalid found: line 2\n# Host example.invalid found: line 5\n"
        let result = try SSHHostTrust.replacingTarget(in: original, lookup: lookup, target: "example.invalid",
                                                     replacement: "example.invalid ssh-ed25519 REVIEWED\n")
        let text = String(decoding: result, as: UTF8.self)
        XCTAssertTrue(text.contains("# user comment\n"))
        XCTAssertTrue(text.contains("alias.invalid ssh-ed25519 OLD\n"))
        XCTAssertTrue(text.contains("[example.invalid]:2222 ssh-ed25519 OTHER_PORT\n"))
        XCTAssertTrue(text.contains("unrelated.invalid ssh-ed25519 UNRELATED\n"))
        XCTAssertFalse(text.contains("OLD_RSA"))
        XCTAssertTrue(text.hasSuffix("example.invalid ssh-ed25519 REVIEWED\n"))
    }

    func testHashedRecordsAndUnsafeRules() throws {
        let lookup = "# Host example.invalid found: line 1\n"
        let hashed = Data("|1|salt|hash ssh-ed25519 OLD\nother.invalid ssh-ed25519 OTHER\n".utf8)
        let result = try SSHHostTrust.replacingTarget(in: hashed, lookup: lookup, target: "example.invalid", replacement: "")
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "\nother.invalid ssh-ed25519 OTHER\n")
        for record in ["@revoked example.invalid ssh-ed25519 OLD", "@cert-authority example.invalid ssh-ed25519 CA",
                       "*.invalid ssh-ed25519 WILDCARD", "!excluded.invalid,example.invalid ssh-ed25519 NEGATED"] {
            XCTAssertThrowsError(try SSHHostTrust.replacingTarget(in: Data(record.utf8), lookup: lookup,
                                                                 target: "example.invalid", replacement: ""))
        }
        XCTAssertThrowsError(try SSHHostTrust.replacingTarget(in: hashed, lookup: "", target: "example.invalid", replacement: ""))
    }

    func testTargetIncludesNonDefaultPortAndIPv6() {
        XCTAssertEqual(SSHHostTrust.target(SSHHost(address: "example.invalid")), "example.invalid")
        XCTAssertEqual(SSHHostTrust.target(SSHHost(address: "::1", port: 2222)), "[::1]:2222")
    }
}
