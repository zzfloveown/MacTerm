import Domain
import Foundation
import SFTPCore
import SSHCore
import XCTest

final class SSHIntegrationTests: XCTestCase {
    func testSSHAndSFTPRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixture = environment["MACTERM_TEST_FIXTURE"],
              let port = environment["MACTERM_TEST_PORT"].flatMap(Int.init),
              let user = environment["MACTERM_TEST_USER"] else {
            throw XCTSkip("需要 GitHub Actions 上的临时 sshd。")
        }
        let host = SSHHost(address: "127.0.0.1", user: user, port: port, identity: fixture + "/user")
        let ssh = OpenSSHTransport()
        let response = try await ssh.execute(on: host, arguments: ["printf", "%s", "round trip ' ;"])
        XCTAssertEqual(response, "round trip ' ;")

        var mismatched = host
        mismatched.address = "localhost"
        do {
            _ = try await ssh.execute(on: mismatched, arguments: ["true"])
            XCTFail("SSH accepted the wrong host key")
        } catch let error as MacTermError {
            XCTAssertTrue(error.message.contains("255"))
        }

        let sftp = SFTPClient()
        let folder = fixture + "/远程 文件"
        try await sftp.createDirectory(folder, on: host)
        let source = fixture + "/source"
        let destination = fixture + "/destination"
        let data = Data((0...255).map(UInt8.init))
        try data.write(to: URL(fileURLWithPath: source))
        let original = folder + "/中文 文件.bin"
        let renamed = folder + "/改名.bin"
        try await sftp.upload(local: source, remote: original, on: host)
        let directory = try await sftp.list(folder, on: host)
        XCTAssertEqual(directory, ["中文 文件.bin"])
        try await sftp.rename(original, to: renamed, on: host)
        try await sftp.download(remote: renamed, local: destination, on: host)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination)), data)
        try await sftp.deleteFile(renamed, on: host)
        let emptied = try await sftp.list(folder, on: host)
        XCTAssertTrue(emptied.isEmpty)
    }
}
