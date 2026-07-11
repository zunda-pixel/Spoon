import Foundation
import Testing

@testable import SpoonCore

@Suite("GitStatusParser")
struct GitStatusParserTests {
  private func parse(_ records: [String]) throws -> WorkingTreeStatus {
    try GitStatusParser.parse(Data((records.joined(separator: "\0") + "\0").utf8))
  }

  @Test func branchHeaders() throws {
    let status = try parse([
      "# branch.oid 4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331",
      "# branch.head main",
      "# branch.upstream origin/main",
      "# branch.ab +2 -1",
    ])
    #expect(status.headOID?.rawValue == "4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331")
    #expect(status.headBranch == "main")
    #expect(status.upstream == "origin/main")
    #expect(status.ahead == 2)
    #expect(status.behind == 1)
    #expect(status.isClean)
  }

  @Test func unbornBranch() throws {
    let status = try parse([
      "# branch.oid (initial)",
      "# branch.head main",
    ])
    #expect(status.headOID == nil)
    #expect(status.headBranch == "main")
  }

  @Test func detachedHead() throws {
    let status = try parse([
      "# branch.oid 4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331",
      "# branch.head (detached)",
    ])
    #expect(status.headBranch == nil)
  }

  @Test func stagedAndUnstagedChanges() throws {
    let hash = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    let status = try parse([
      "1 M. N... 100644 100644 100644 \(hash) \(hash) staged.txt",
      "1 .M N... 100644 100644 100644 \(hash) \(hash) unstaged.txt",
      "1 MM N... 100644 100644 100644 \(hash) \(hash) both.txt",
      "1 A. N... 000000 100644 100644 \(String(repeating: "0", count: 40)) \(hash) new.txt",
      "1 .D N... 100644 100644 000000 \(hash) \(hash) gone.txt",
    ])
    #expect(status.entries.count == 5)
    #expect(status.entries[0].staged == .modified)
    #expect(status.entries[0].unstaged == nil)
    #expect(status.entries[1].staged == nil)
    #expect(status.entries[1].unstaged == .modified)
    #expect(status.entries[2].staged == .modified)
    #expect(status.entries[2].unstaged == .modified)
    #expect(status.entries[3].staged == .added)
    #expect(status.entries[4].unstaged == .deleted)
    #expect(status.stagedEntries.count == 3)
    #expect(status.unstagedEntries.count == 3)
    #expect(!status.isClean)
  }

  @Test func pathsWithSpacesAndUnicode() throws {
    let hash = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    let status = try parse([
      "1 M. N... 100644 100644 100644 \(hash) \(hash) path with spaces.txt",
      "1 .M N... 100644 100644 100644 \(hash) \(hash) 日本語ファイル.swift",
    ])
    #expect(status.entries[0].path == "path with spaces.txt")
    #expect(status.entries[1].path == "日本語ファイル.swift")
  }

  @Test func renameConsumesFollowingToken() throws {
    let hash = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    let status = try parse([
      "2 R. N... 100644 100644 100644 \(hash) \(hash) R100 new name.txt",
      "old name.txt",
      "1 .M N... 100644 100644 100644 \(hash) \(hash) after.txt",
    ])
    #expect(status.entries.count == 2)
    #expect(status.entries[0].path == "new name.txt")
    #expect(status.entries[0].originalPath == "old name.txt")
    #expect(status.entries[0].staged == .renamed)
    #expect(status.entries[1].path == "after.txt")
  }

  @Test(arguments: [
    ("UU", FileStatusEntry.Conflict.bothModified),
    ("AA", .bothAdded),
    ("DD", .bothDeleted),
    ("AU", .addedByUs),
    ("UA", .addedByThem),
    ("DU", .deletedByUs),
    ("UD", .deletedByThem),
  ])
  func unmergedEntries(xy: String, expected: FileStatusEntry.Conflict) throws {
    let hash = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
    let status = try parse([
      "u \(xy) N... 100644 100644 100644 100644 \(hash) \(hash) \(hash) conflicted.txt"
    ])
    #expect(status.entries[0].conflict == expected)
    #expect(status.conflictedEntries.count == 1)
  }

  @Test func untrackedAndIgnored() throws {
    let status = try parse([
      "? untracked.txt",
      "! build/output.o",
    ])
    #expect(status.entries[0].isUntracked)
    #expect(status.entries[1].isIgnored)
    #expect(status.untrackedEntries.count == 1)
    // Ignored-only worktrees still count as clean.
    #expect(try parse(["! build/output.o"]).isClean)
  }

  @Test func unknownHeadersAreIgnored() throws {
    let status = try parse([
      "# stash 3",
      "# branch.head main",
    ])
    #expect(status.headBranch == "main")
  }

  @Test func malformedRecordThrows() {
    #expect(throws: GitStatusParser.ParseError.self) {
      try parse(["Z bogus record"])
    }
  }

  @Test func emptyOutputIsCleanStatus() throws {
    let status = try GitStatusParser.parse(Data())
    #expect(status.entries.isEmpty)
    #expect(status.isClean)
  }
}
