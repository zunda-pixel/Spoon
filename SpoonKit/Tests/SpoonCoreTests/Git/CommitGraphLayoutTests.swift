import Foundation
import Testing

@testable import SpoonCore

@Suite("CommitGraphLayout")
struct CommitGraphLayoutTests {
  private func oid(_ char: Character) -> ObjectID {
    // Derive a valid unique hex oid from any letter ("m", "x", …).
    var hexPair = String(char.asciiValue ?? 0, radix: 16)
    if hexPair.count == 1 { hexPair = "0" + hexPair }
    return ObjectID(rawValue: String(repeating: hexPair, count: 20))!
  }

  private func commit(_ char: Character, parents: [Character]) -> Commit {
    Commit(
      oid: oid(char),
      parents: parents.map(oid),
      subject: "commit \(char)",
      authorName: "A",
      authorEmail: "a@example.com",
      authoredAt: Date(timeIntervalSince1970: 0),
      committedAt: Date(timeIntervalSince1970: 0)
    )
  }

  @Test func linearHistoryStaysInLaneZero() {
    // c → b → a (newest first)
    let rows = CommitGraphLayout.assignLanes([
      commit("c", parents: ["b"]),
      commit("b", parents: ["a"]),
      commit("a", parents: []),
    ])
    #expect(rows.map(\.lane) == [0, 0, 0])
    #expect(rows.map(\.laneCount) == [1, 1, 1])
    // Tip has no incoming edge; root has no outgoing edge.
    #expect(rows[0].edges == [.outOfCommit(to: 0)])
    #expect(rows[1].edges == [.intoCommit(from: 0), .outOfCommit(to: 0)])
    #expect(rows[2].edges == [.intoCommit(from: 0)])
  }

  @Test func mergeCommitForksAndJoins() {
    // m is a merge of b (mainline) and f (feature); both parented on a.
    //   m
    //   |\
    //   b f
    //   |/
    //   a
    let rows = CommitGraphLayout.assignLanes([
      commit("m", parents: ["b", "f"]),
      commit("b", parents: ["a"]),
      commit("f", parents: ["a"]),
      commit("a", parents: []),
    ])
    #expect(rows[0].lane == 0)
    #expect(rows[0].edges.contains(.outOfCommit(to: 0)))
    #expect(rows[0].edges.contains(.outOfCommit(to: 1)))  // fork to feature lane

    #expect(rows[1].lane == 0)
    #expect(rows[1].edges.contains(.pass(from: 1, to: 1)))  // feature passes through

    #expect(rows[2].lane == 1)
    #expect(rows[2].edges.contains(.pass(from: 0, to: 0)))  // mainline passes through

    // Both lanes converge on the shared root.
    #expect(rows[3].lane == 0)
    #expect(rows[3].edges.contains(.intoCommit(from: 0)))
    #expect(rows[3].edges.contains(.intoCommit(from: 1)))
    #expect(rows[3].laneCount == 2)
  }

  @Test func independentBranchTipsGetSeparateLanes() {
    // Two unrelated tips run in parallel: x → a, y → b.
    let rows = CommitGraphLayout.assignLanes([
      commit("x", parents: ["a"]),
      commit("y", parents: ["b"]),
      commit("a", parents: []),
      commit("b", parents: []),
    ])
    #expect(rows[0].lane == 0)
    #expect(rows[1].lane == 1)
    #expect(rows[2].lane == 0)
    #expect(rows[3].lane == 1)
  }

  @Test func rootCommitFreesItsLaneForLaterTips() {
    // x → a (root), then unrelated tip y should reuse lane 0.
    let rows = CommitGraphLayout.assignLanes([
      commit("x", parents: ["a"]),
      commit("a", parents: []),
      commit("y", parents: []),
    ])
    #expect(rows[2].lane == 0)
  }

  @Test func mergeParentSharedWithExistingLaneJoinsIt() {
    // m merges b and a, where a is already awaited by lane 0 through b?
    // Simpler shape: t → a; m → (b, a); order [t, m, b, a].
    let rows = CommitGraphLayout.assignLanes([
      commit("t", parents: ["a"]),
      commit("m", parents: ["b", "a"]),
      commit("b", parents: []),
      commit("a", parents: []),
    ])
    // m sits in lane 1; its second parent `a` is already awaited in lane 0,
    // so the merge routes into lane 0 instead of allocating lane 2.
    #expect(rows[1].lane == 1)
    #expect(rows[1].edges.contains(.outOfCommit(to: 0)))
    #expect(rows.map(\.laneCount).max() == 2)
  }

  @Test func emptyInputYieldsNoRows() {
    #expect(CommitGraphLayout.assignLanes([]).isEmpty)
  }
}
