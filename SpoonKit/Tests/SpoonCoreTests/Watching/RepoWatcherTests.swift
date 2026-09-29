import Foundation
import Testing

@testable import SpoonCore

@Suite("RepoWatcher")
struct RepoWatcherTests {
  private let root = URL(filePath: "/repo", directoryHint: .isDirectory)
  private var layout: RepoWatcher.Layout { RepoWatcher.Layout(root: root) }
  /// A linked worktree at /wt whose metadata lives in /repo/.git.
  private let linked = RepoWatcher.Layout(
    root: URL(filePath: "/wt", directoryHint: .isDirectory),
    gitDirectory: URL(filePath: "/repo/.git/worktrees/wt", directoryHint: .isDirectory),
    commonDirectory: URL(filePath: "/repo/.git", directoryHint: .isDirectory)
  )

  @Test func gitTopLevelMeansIndexAndRefs() {
    let changes = RepoWatcher.classify(["/repo/.git/"], layout: layout)
    #expect(changes == [.index, .refs])
  }

  @Test func refsDirectoryMeansRefs() {
    let changes = RepoWatcher.classify(["/repo/.git/refs/heads/"], layout: layout)
    #expect(changes == [.refs])
  }

  @Test func objectsAndLogsAreIgnored() {
    let changes = RepoWatcher.classify(
      ["/repo/.git/objects/ab/", "/repo/.git/logs/", "/repo/.git/objects/pack/"],
      layout: layout
    )
    #expect(changes.isEmpty)
  }

  @Test func sourceDirectoryMeansWorktree() {
    let changes = RepoWatcher.classify(["/repo/Sources/App/"], layout: layout)
    #expect(changes == [.worktree])
  }

  @Test func buildArtifactsAreIgnored() {
    let changes = RepoWatcher.classify(
      ["/repo/.build/debug/", "/repo/DerivedData/x/", "/repo/node_modules/y/"],
      layout: layout
    )
    #expect(changes.isEmpty)
  }

  @Test func pathsOutsideRootAreIgnored() {
    let changes = RepoWatcher.classify(["/elsewhere/dir/"], layout: layout)
    #expect(changes.isEmpty)
  }

  @Test func mixedBatchUnions() {
    let changes = RepoWatcher.classify(
      ["/repo/.git/refs/heads/", "/repo/Sources/"],
      layout: layout
    )
    #expect(changes == [.refs, .worktree])
  }

  @Test func siblingDirectoryWithSharedPrefixIsIgnored() {
    let changes = RepoWatcher.classify(["/repository/Sources/"], layout: layout)
    #expect(changes.isEmpty)
  }

  @Test func linkedWorktreeGitDirectoryMeansIndexAndRefs() {
    let changes = RepoWatcher.classify(["/repo/.git/worktrees/wt/"], layout: linked)
    #expect(changes == [.index, .refs])
  }

  @Test func linkedWorktreeSeesSharedRefsAndPackedRefs() {
    #expect(RepoWatcher.classify(["/repo/.git/refs/heads/"], layout: linked) == [.refs])
    #expect(RepoWatcher.classify(["/repo/.git/"], layout: linked) == [.refs])
  }

  @Test func linkedWorktreeIgnoresOtherWorktreesAndObjects() {
    let changes = RepoWatcher.classify(
      ["/repo/.git/worktrees/other/", "/repo/.git/objects/ab/", "/repo/Sources/"],
      layout: linked
    )
    #expect(changes.isEmpty)
  }

  @Test func linkedWorktreeFilesMeanWorktree() {
    #expect(RepoWatcher.classify(["/wt/Sources/"], layout: linked) == [.worktree])
  }

  @Test func watchedDirectoriesCollapseNestedMetadata() {
    #expect(layout.watchedDirectories == [root])
    #expect(linked.watchedDirectories == [linked.root, linked.commonDirectory])
  }
}
