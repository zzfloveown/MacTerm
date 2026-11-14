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
        let directory = try await sftp.entries(folder, on: host)
        XCTAssertEqual(directory.map(\.name), ["中文 文件.bin"])
        XCTAssertEqual(directory.first?.size, UInt64(data.count))
        XCTAssertNotNil(directory.first?.modified)
        try await sftp.setPermissions(0o600, at: original, on: host)
        let updated = try await sftp.entries(folder, on: host)
        XCTAssertEqual(updated.first?.permissions.map { $0 & 0o777 }, 0o600)
        try await sftp.rename(original, to: renamed, on: host)
        try await sftp.download(remote: renamed, local: destination, on: host)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination)), data)
        let uploadID = UUID()
        let resumed = folder + "/resume.bin"
        let remotePartial = resumed + ".macterm-" + uploadID.uuidString.lowercased() + ".part"
        try data.prefix(100).write(to: URL(fileURLWithPath: remotePartial))
        try await sftp.transfer(local: URL(fileURLWithPath: source), remote: resumed,
                                on: host, upload: true, id: uploadID) { _ in }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: resumed)), data)

        let downloadID = UUID()
        let resumedDownload = URL(fileURLWithPath: fixture + "/resumed-download")
        let localPartial = resumedDownload.appendingPathExtension("macterm-" + downloadID.uuidString.lowercased() + ".part")
        try Data([255]).write(to: localPartial)
        do {
            try await sftp.transfer(local: resumedDownload, remote: resumed, on: host, upload: false, id: downloadID) { _ in }
            XCTFail("Resume accepted data that did not match")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: resumedDownload.path))
        }
        try data.prefix(100).write(to: localPartial)
        try await sftp.transfer(local: resumedDownload, remote: resumed, on: host, upload: false, id: downloadID) { _ in }
        XCTAssertEqual(try Data(contentsOf: resumedDownload), data)
        try await sftp.deleteFile(resumed, on: host)
        try await sftp.deleteFile(renamed, on: host)
        let emptied = try await sftp.list(folder, on: host)
        XCTAssertTrue(emptied.isEmpty)
    }
}
