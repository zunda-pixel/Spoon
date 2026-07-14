import Foundation
import Testing

@testable import SpoonCore

@Suite("HistoryReferenceLabelBuilder")
struct HistoryReferenceLabelBuilderTests {
  @Test func groupsEveryReferenceKindAndPrioritizesFocusedBranch() throws {
    let oid = try #require(ObjectID(rawValue: String(repeating: "a", count: 40)))
    let local = Branch(
      name: "main",
      isCurrent: true,
      tip: oid,
      subject: "Main",
      upstream: "origin/main",
      ahead: 0,
      behind: 0,
      committedAt: nil
    )
    let remote = Branch(
      name: "origin/main",
      isCurrent: false,
      tip: oid,
      subject: "Remote",
      upstream: nil,
      ahead: nil,
      behind: nil,
      committedAt: nil
    )
    let focus = HistoryReferenceIdentity.remoteBranch(
      remote: "origin",
      name: remote.name
    )

    let labels = HistoryReferenceLabelBuilder.build(
      branches: [local],
      remoteBranchesByRemote: ["origin": [remote]],
      worktrees: [
        Worktree(
          path: URL(filePath: "/tmp/Spoon-main"),
          branch: "main",
          headOID: oid,
          isMain: false
        )
      ],
      tags: [Tag(name: "v1.0", target: oid, isAnnotated: true, createdAt: nil)],
      stashes: [Stash(index: 0, target: oid, message: "WIP")],
      activeWorktreeRoot: URL(filePath: "/tmp/Spoon-main"),
      selectedReference: focus
    )

    let commitLabels = try #require(labels[oid])
    #expect(commitLabels.count == 5)
    #expect(commitLabels.first?.referenceIdentity == focus)
    #expect(commitLabels.first(where: { $0.kind == .worktree })?.isCurrent == true)
    #expect(
      Set(commitLabels.map(\.kind))
        == Set([.localBranch, .remoteBranch, .worktree, .tag, .stash])
    )
  }

  @Test func remoteIdentityIncludesRemoteWhenBranchNamesMatch() throws {
    let oid = try #require(ObjectID(rawValue: String(repeating: "b", count: 40)))
    let originBranch = branch(name: "origin/topic", oid: oid)
    let upstreamBranch = branch(name: "upstream/topic", oid: oid)
    let selected = HistoryReferenceIdentity.remoteBranch(
      remote: "upstream",
      name: "upstream/topic"
    )

    let labels = HistoryReferenceLabelBuilder.build(
      branches: [],
      remoteBranchesByRemote: [
        "origin": [originBranch],
        "upstream": [upstreamBranch],
      ],
      worktrees: [],
      tags: [],
      stashes: [],
      selectedReference: selected
    )

    let remoteLabels = try #require(labels[oid])
    #expect(remoteLabels.count == 2)
    #expect(remoteLabels.first?.referenceIdentity == selected)
    #expect(
      Set(remoteLabels.map(\.id))
        == ["remote:origin:origin/topic", "remote:upstream:upstream/topic"]
    )
  }

  @Test func omitsWorktreesWithoutAHeadCommit() throws {
    let labels = HistoryReferenceLabelBuilder.build(
      branches: [],
      remoteBranchesByRemote: [:],
      worktrees: [
        Worktree(
          path: URL(filePath: "/tmp/bare"),
          branch: nil,
          headOID: nil,
          isMain: false
        )
      ],
      tags: [],
      stashes: []
    )

    #expect(labels.isEmpty)
  }

  private func branch(name: String, oid: ObjectID) -> Branch {
    Branch(
      name: name,
      isCurrent: false,
      tip: oid,
      subject: name,
      upstream: nil,
      ahead: nil,
      behind: nil,
      committedAt: nil
    )
  }
}
