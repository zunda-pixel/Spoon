import Foundation
import Testing

@testable import SpoonCore

@Suite("Git output helpers")
struct GitOutputHelperTests {
  @Test func remoteParserPreservesOrderAndDistinctPushURL() {
    let remotes = GitRemoteParser.parse(
      """
      origin\tgit@example.com:owner/repo.git (fetch)
      origin\tgit@example.com:owner/repo.git (push)
      fork\thttps://example.com/fork.git (fetch)
      fork\tssh://example.com/fork.git (push)
      """
    )

    #expect(remotes.map(\.name) == ["origin", "fork"])
    #expect(remotes[0].pushURL == nil)
    #expect(remotes[1].pushURL == "ssh://example.com/fork.git")
  }

  @Test func stashParserSkipsMalformedRecords() {
    let data = Data(
      "stash@{2}\u{1f}On main: useful\u{0}"
        .appending("malformed\u{0}")
        .appending("stash@{0}\u{1f}\u{0}")
        .utf8
    )

    let stashes = GitStashParser.parse(data)

    #expect(stashes.map(\.index) == [2, 0])
    #expect(stashes.map(\.message) == ["On main: useful", ""])
  }

  @Test(
    arguments: [
      ("git version 2.48.1", false),
      ("git version 2.49.0", true),
      ("git version 3.0.0", true),
      ("unexpected output", false),
    ]
  )
  func versionParserDetectsBackfill(output: String, expected: Bool) {
    #expect(GitVersionParser.supportsBackfill(output) == expected)
  }

  @Test func untrackedDiffBuilderCreatesTextPatch() {
    let diff = UntrackedDiffBuilder.make(path: "notes.txt", data: Data("first\nsecond".utf8))

    #expect(diff.kind == .added)
    #expect(diff.additionCount == 2)
    #expect(diff.hunks.first?.header == "@@ -0,0 +1,2 @@")
    #expect(diff.hunks.first?.lines.last?.kind == .noNewlineMarker)
  }

  @Test func untrackedDiffBuilderDetectsBinaryData() {
    let diff = UntrackedDiffBuilder.make(path: "image.bin", data: Data([1, 0, 2]))

    #expect(diff.kind == .added)
    #expect(diff.isBinary)
    #expect(diff.hunks.isEmpty)
  }
}
