import Foundation
import Testing

@testable import SpoonCore

@Suite("Archive")
struct ArchiveTests {
  private let runner = SubprocessCommandRunner()

  @Test(arguments: [
    ("Spoon-1.0.zip", ArchiveFormat.zip), ("Spoon.TAR.GZ", .tarGz), ("spoon.tgz", .tarGz),
    ("spoon.tar", .tar), ("spoon", .zip),
  ])
  func formatFollowsTheFileExtension(name: String, format: ArchiveFormat) {
    #expect(ArchiveFormat(fileName: name) == format)
  }

  @Test(arguments: [ArchiveFormat.zip, .tarGz])
  func archivesTheRevisionUnderItsPrefixFolder(format: ArchiveFormat) async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "README.md", content: "v1\n", message: "first"),
        .init(file: "Sources/App.swift", content: "app\n", message: "second"),
      ],
      runner: runner)
    let output = URL.temporaryDirectory.appending(path: "spoon-archive-\(UUID().uuidString).\(format.rawValue)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: output)
    }
    try await LiveRepoFixture.run(["tag", "v1", "HEAD~1"], in: root, runner: runner)
    // Uncommitted edits stay out of the archive.
    try Data("edited\n".utf8).write(to: root.appending(path: "README.md"))
    let client = LiveRepoFixture.makeClient(for: root, runner: runner)

    try await client.archive("refs/tags/v1", format: format, prefix: "demo-v1", to: output)

    let list = Process()
    list.executableURL = URL(filePath: format == .zip ? "/usr/bin/zipinfo" : "/usr/bin/tar")
    list.arguments = format == .zip ? ["-1", output.path] : ["-tzf", output.path]
    let pipe = Pipe()
    list.standardOutput = pipe
    try list.run()
    list.waitUntilExit()
    let entries = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .split(separator: "\n").map(String.init)
    #expect(entries.sorted() == ["demo-v1/", "demo-v1/README.md"])
  }
}
