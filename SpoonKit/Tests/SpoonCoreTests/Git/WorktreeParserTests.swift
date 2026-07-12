import Foundation
import Testing

@testable import SpoonCore

@Suite("WorktreeParser")
struct WorktreeParserTests {
  @Test func parsesMainLinkedAndDetachedEntries() {
    let fixture = """
      worktree /Users/z/repo
      HEAD 1111222233334444
      branch refs/heads/main

      worktree /Users/z/repo-feature
      HEAD 5555666677778888
      branch refs/heads/feature/login

      worktree /Users/z/detached wt
      HEAD 9999aaaabbbbcccc
      detached

      """
    let worktrees = WorktreeParser.parse(Data(fixture.utf8))
    #expect(worktrees.count == 3)

    #expect(worktrees[0].isMain)
    #expect(worktrees[0].branch == "main")
    #expect(worktrees[0].path.path == "/Users/z/repo")
    #expect(worktrees[0].headOID?.rawValue == "1111222233334444")

    #expect(!worktrees[1].isMain)
    #expect(worktrees[1].branch == "feature/login")

    #expect(worktrees[2].branch == nil)
    #expect(worktrees[2].path.path == "/Users/z/detached wt")
  }

  @Test func missingTrailingBlankLineStillFlushesLastEntry() {
    let fixture = "worktree /repo\nHEAD 1234abcd\nbranch refs/heads/main"
    let worktrees = WorktreeParser.parse(Data(fixture.utf8))
    #expect(worktrees.count == 1)
    #expect(worktrees[0].branch == "main")
  }

  @Test func emptyInputParsesToNoWorktrees() {
    #expect(WorktreeParser.parse(Data()).isEmpty)
  }
}
