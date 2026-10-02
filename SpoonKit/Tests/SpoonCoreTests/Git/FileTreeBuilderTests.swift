import Foundation
import Testing

@testable import SpoonCore

@Suite("FileTreeBuilder")
struct FileTreeBuilderTests {
  private func entry(_ path: String) -> FileStatusEntry {
    FileStatusEntry(path: path, unstaged: .modified)
  }

  @Test func foldsSingleChildDirectoryChains() throws {
    let tree = FileTreeBuilder.build([entry("a/b/c/file.swift")])
    let directory = try #require(tree.first)
    #expect(tree.count == 1)
    #expect(directory.name == "a/b/c")
    #expect(directory.path == "a/b/c")
    #expect(directory.children?.map(\.name) == ["file.swift"])
    #expect(directory.children?.first?.entry?.path == "a/b/c/file.swift")
  }

  @Test func foldingStopsAtBranchPoints() throws {
    let tree = FileTreeBuilder.build([entry("a/b/x.swift"), entry("a/c/y.swift")])
    let root = try #require(tree.first)
    #expect(root.name == "a")
    #expect(root.children?.map(\.name) == ["b", "c"])
  }

  @Test func directoriesSortBeforeFilesAlphabetically() {
    let tree = FileTreeBuilder.build([
      entry("zebra.txt"),
      entry("alpha.txt"),
      entry("beta/inner.txt"),
      entry("apple/inner.txt"),
    ])
    #expect(tree.map(\.name) == ["apple", "beta", "alpha.txt", "zebra.txt"])
    #expect(tree[0].children != nil)
    #expect(tree[2].children == nil)
  }

  @Test func untrackedDirectoryEntriesKeepTheirTrailingSlash() {
    let tree = FileTreeBuilder.build([entry("assets/")])
    #expect(tree.map(\.name) == ["assets/"])
    #expect(tree[0].entry?.path == "assets/")
    #expect(tree[0].children == nil)
  }

  @Test func rootOnlyFilesAndEmptyInput() {
    #expect(FileTreeBuilder.build([]).isEmpty)
    let flat = FileTreeBuilder.build([entry("README.md")])
    #expect(flat.count == 1)
    #expect(flat[0].entry?.path == "README.md")
    #expect(flat[0].children == nil)
  }

  @Test func leafEntriesFollowDepthFirstDisplayOrder() {
    let tree = FileTreeBuilder.build([
      entry("zebra.txt"),
      entry("src/lib/util.swift"),
      entry("src/app/main.swift"),
      entry("docs/readme.md"),
    ])
    let leaves = FileTreeBuilder.leafEntries(tree).map(\.path)
    #expect(
      leaves == ["docs/readme.md", "src/app/main.swift", "src/lib/util.swift", "zebra.txt"]
    )
  }

  @Test func areaTreesGiveTheSamePathDistinctIDs() {
    var status = WorkingTreeStatus()
    status.entries = [
      FileStatusEntry(path: "Sources/App/a.swift", staged: .modified, unstaged: .modified),
      FileStatusEntry(path: "Sources/App/b.swift", isUntracked: true),
    ]

    let trees = ChangeTrees(status: status)
    let ids = [trees.staged, trees.unstaged, trees.untracked].flatMap { allIDs($0) }

    #expect(Set(ids).count == ids.count)
    #expect(trees.staged.first?.path == trees.unstaged.first?.path)
  }

  @Test func refoldingGivesMovedNodesNewIDs() {
    let folded = FileTreeBuilder.build([entry("Kit/App/TabBar/Main.swift")])
    let split = FileTreeBuilder.build([
      entry("Kit/App/TabBar/Main.swift"), entry("Kit/Features/Home.swift"),
    ])

    // Kit/App/TabBar and its file move under a new Kit row; reusing their
    // IDs would move rows across parents in the outline.
    #expect(Set(allIDs(folded)).isDisjoint(with: allIDs(split)))
    #expect(Set(allIDs(split)).count == allIDs(split).count)
    #expect(split.first?.children?.first?.path == folded.first?.path)
  }

  private func allIDs(_ nodes: [FileTreeNode]) -> [String] {
    nodes.flatMap { [$0.id] + allIDs($0.children ?? []) }
  }
}
