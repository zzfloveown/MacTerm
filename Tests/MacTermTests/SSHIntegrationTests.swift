import Domain
import Foundation
import Infrastructure
import SFTPCore
import SSHCore
import XCTest

final class SSHIntegrationTests: XCTestCase {
    func testLocalForwardAndPortConflict() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let fixture = env["MACTERM_TEST_FIXTURE"],
              let port = env["MACTERM_TEST_PORT"].flatMap(Int.init),
              let user = env["MACTERM_TEST_USER"] else {
            throw XCTSkip("需要 GitHub Actions 上的临时 sshd。")
        }
        let host = SSHHost(address: "127.0.0.1", user: user, port: port, identity: fixture + "/user")
        let transport = OpenSSHTransport()
        let ready = expectation(description: "SSH local forwarding established")
        let forward = Task {
            try await transport.forward(on: host, mode: .local, port: 40223, destination: "127.0.0.1",
                                        destinationPort: port) { ready.fulfill() }
        }
        defer { forward.cancel() }
        await fulfillment(of: [ready], timeout: 16)
        let alias = "[127.0.0.1]:\(port)"
        let result = try await ProcessRunner.run("/usr/bin/ssh", [
            "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=\(alias)", "-o", "ConnectTimeout=5", "-o", "IdentitiesOnly=yes",
            "-i", host.identity, "-p", "40223", "-l", user, "127.0.0.1", "printf ready"
        ])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.text, "ready")
        do {
            try await transport.forward(on: host, mode: .dynamic, port: 40223, destination: "",
                                        destinationPort: 0)
            XCTFail("Duplicate listener was accepted")
        } catch { XCTAssertTrue(error is MacTermError) }
        forward.cancel()
        do { try await forward.value; XCTFail("Cancellation was ignored") }
        catch is CancellationError {}
    }

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

        var chained = host
        chained.jump = "\(user)@127.0.0.1:40225,\(user)@127.0.0.1:40226"
        let jumped = try await ssh.execute(on: chained, arguments: ["printf", "two-jumps"])
        XCTAssertEqual(jumped, "two-jumps")

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
        let textPath = folder + "/edit.txt"
        try Data("原文".utf8).write(to: URL(fileURLWithPath: textPath))
        let originalText = try await sftp.readText(at: textPath, on: host)
        XCTAssertEqual(originalText.text, "原文")
        try await sftp.writeText("修改", basedOn: originalText, at: textPath, on: host)
        let modified = try await sftp.readText(at: textPath, on: host)
        XCTAssertEqual(modified.text, "修改")
        do {
            try await sftp.writeText("旧版本覆盖", basedOn: originalText, at: textPath, on: host)
            XCTFail("Stale edits were accepted")
        } catch {
            XCTAssertEqual(try String(contentsOfFile: textPath, encoding: .utf8), "修改")
        }
        try await sftp.deleteFile(textPath, on: host)
        try await sftp.deleteFile(resumed, on: host)
        try await sftp.deleteFile(renamed, on: host)
        let emptied = try await sftp.list(folder, on: host)
        XCTAssertTrue(emptied.isEmpty)
    }
}
