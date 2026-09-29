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
      ("git version 2.48.1", GitVersion(2, 48, 1)),
      ("git version 2.39.5 (Apple Git-154)", GitVersion(2, 39, 5)),
      ("git version 2.56.0.rc2", GitVersion(2, 56, 0)),
      ("git version 3.0", GitVersion(3, 0, 0)),
      ("unexpected output", nil),
    ]
  )
  func versionParserReadsReleaseNumbers(output: String, expected: GitVersion?) {
    #expect(GitVersionParser.parse(output) == expected)
  }

  @Test(
    arguments: [
      (GitVersion(2, 48, 1), false),
      (GitVersion(2, 49, 0), true),
      (GitVersion(3, 0, 0), true),
      (nil, false),
    ] as [(GitVersion?, Bool)]
  )
  func capabilitiesGateBackfillOnVersion(version: GitVersion?, expected: Bool) {
    #expect(GitCapabilities(version: version).supportsBackfill == expected)
  }

  @Test func repositoryPathsParserRejectsIncompleteOrRelativeOutput() {
    let gitDirectoryOnly = Data("path.gitdir.absolute\n/r/.git\u{0}".utf8)
    #expect(GitRepositoryPathsParser.parseRepoInfo(gitDirectoryOnly) == nil)
    #expect(GitRepositoryPathsParser.parseRevParse(".git\n.git\n") == nil)
    #expect(GitRepositoryPathsParser.parseRevParse("/r/.git\n") == nil)
  }

  @Test func refUpdateParserReadsUpdateRefStdinLines() {
    let new = String(repeating: "1", count: 40)
    let old = String(repeating: "2", count: 40)
    let updates = RefUpdateParser.parse(
      """
      update refs/heads/feature/a \(new) \(old)
      update HEAD \(new) \(old)
      warning: ignored
      update refs/heads/bad not-an-oid \(old)

      """
    )

    #expect(updates.map(\.reference) == ["refs/heads/feature/a", "HEAD"])
    #expect(updates.map(\.branchName) == ["feature/a", nil])
    #expect(updates.first?.newOID.rawValue == new)
    #expect(updates.first?.oldOID.rawValue == old)
  }

  @Test func signatureParserMapsVerificationLetters() {
    let good = GitSignatureParser.parse(
      "G\u{1f}Jane <jane@example.com>\u{1f}ABCD\u{1f}SHA256:xyz\n"
    )
    #expect(
      good == CommitSignature(status: .good, signer: "Jane <jane@example.com>", key: "SHA256:xyz")
    )
    #expect(GitSignatureParser.parse("E\u{1f}\u{1f}ABCD\u{1f}\n")?.key == "ABCD")
    #expect(GitSignatureParser.parse("B\u{1f}\u{1f}\u{1f}")?.status.isValid == false)
    #expect(GitSignatureParser.parse("N\u{1f}\u{1f}\u{1f}\n") == nil)
    #expect(GitSignatureParser.parse("") == nil)
  }

  @Test func stashOptionsBuildPushArguments() {
    #expect(StashSaveOptions().arguments.isEmpty)
    #expect(
      StashSaveOptions(message: " wip ", includeUntracked: true, paths: ["a.txt", "-odd"])
        .arguments == ["--include-untracked", "-m", "wip", "--", "a.txt", "-odd"]
    )
    #expect(StashSaveOptions(scope: .stagedOnly, includeUntracked: true).arguments == ["--staged"])
    #expect(
      StashSaveOptions(scope: .keepingIndex, includeUntracked: true).arguments
        == ["--keep-index", "--include-untracked"]
    )
  }

  @Test func blameParserReusesCommitHeadersAcrossLines() {
    let first = String(repeating: "a", count: 40)
    let zero = String(repeating: "0", count: 40)
    let output = """
      \(first) 1 1 2
      author Jane
      author-mail <jane@example.com>
      author-time 1700000000
      summary Add file
      filename f.txt
      \tline one
      \(first) 2 2
      \t\ttabbed line
      \(zero) 3 3 1
      author Not Committed Yet
      author-time 1800000000
      summary Version of f.txt from f.txt
      filename f.txt
      \t
      """

    let lines = GitBlameParser.parse(Data(output.utf8))

    #expect(lines.map(\.lineNumber) == [1, 2, 3])
    #expect(lines.map(\.text) == ["line one", "\ttabbed line", ""])
    #expect(lines[1].commit.authorName == "Jane")
    #expect(lines[1].commit.summary == "Add file")
    #expect(!lines[0].commit.isUncommitted)
    #expect(lines[2].commit.isUncommitted)
  }

  @Test func bisectParserReadsRefsAndProgress() {
    let bad = String(repeating: "b", count: 40)
    let good = String(repeating: "a", count: 40)
    let skip = String(repeating: "c", count: 40)
    let state = GitBisectParser.parseRefs(
      "refs/bisect/bad\t\(bad)\nrefs/bisect/good-\(good)\t\(good)\nrefs/bisect/skip-\(skip)\t\(skip)\n"
    )
    #expect(state.badOID?.rawValue == bad)
    #expect(state.goodOIDs.map(\.rawValue) == [good])
    #expect(state.skippedOIDs.map(\.rawValue) == [skip])

    #expect(
      GitBisectParser.parseProgress(
        "Bisecting: 3 revisions left to test after this (roughly 2 steps)\n[\(skip)] Some subject\n"
      ) == .testing(ObjectID(rawValue: skip))
    )
    #expect(
      GitBisectParser.parseProgress("\(bad) is the first bad commit\ncommit \(bad)\n")
        == .found(ObjectID(rawValue: bad)!)
    )
    #expect(BisectState(remainingCount: 7).estimatedStepsLeft == 3)
    #expect(BisectState(remainingCount: 1).estimatedStepsLeft == 0)
  }

  @Test func pullOptionsBuildArguments() {
    #expect(PullOptions().arguments.isEmpty)
    #expect(
      PullOptions(strategy: .rebase, autostash: true).arguments == ["--rebase", "--autostash"]
    )
    #expect(PullOptions(strategy: .merge).arguments == ["--no-rebase"])
    #expect(PullOptions(strategy: .fastForwardOnly).arguments == ["--ff-only"])
  }

  @Test func rangeDiffParserReadsPairingsAndPatchChanges() {
    let output = """
      1:  4901b4d = 1:  916899b add one
      2:  8e3c00b ! 2:  6058041 add two: with = and ! in it
          @@ Metadata
            ## two ##
          -2
          +22

      3:  04d7a9e < -:  ------- add three
      -:  ------- > 3:  0d95c2f add four
      """

    let entries = GitRangeDiffParser.parse(output)

    #expect(entries.map(\.relation) == [.unchanged, .changed, .removed, .added])
    #expect(entries[1].subject == "add two: with = and ! in it")
    #expect(entries[1].patchDiff == ["@@ Metadata", "  ## two ##", "-2", "+22"])
    #expect(entries[2].newOID == nil && entries[2].newPosition == nil)
    #expect(entries[3].oldOID == nil && entries[3].newPosition == 3)
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
