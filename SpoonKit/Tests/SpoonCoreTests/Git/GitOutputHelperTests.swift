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
      "aaaa1111\u{1f}11111111 22222222 33333333\u{1f}stash@{2}\u{1f}On main: useful\u{0}"
        .appending("not-hex\u{1f}11111111 22222222\u{1f}stash@{1}\u{1f}bad target\u{0}")
        .appending("bbbb2222\u{1f}11111111\u{1f}not-a-stash\u{1f}bad reference\u{0}")
        .appending("cccc3333\u{1f}11111111\u{1f}stash@{-1}\u{1f}bad index\u{0}")
        .appending("dddd4444\u{1f}11111111\u{1f}stash@{0}\u{1f}\u{0}")
        .appending("eeee5555\u{1f}bad-parent\u{1f}stash@{3}\u{1f}bad parent\u{0}")
        .utf8
    )

    let stashes = GitStashParser.parse(data)

    #expect(stashes.map(\.index) == [2, 0])
    #expect(stashes.map(\.target.rawValue) == ["aaaa1111", "dddd4444"])
    #expect(stashes[0].helperCommitOIDs.map(\.rawValue) == ["22222222", "33333333"])
    #expect(stashes[1].helperCommitOIDs.isEmpty)
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
