import SpoonCore
import Testing
@testable import SpoonUI

@MainActor
@Suite("Reset current branch to sidebar branch")
struct ResetCurrentBranchToSidebarBranchTests {
  @Test("Current branch is not an available reset target")
  func currentBranchIsNotAvailable() throws {
    let main = try branch(name: "main", isCurrent: true, oid: "aaaaaaaa")
    let feature = try branch(name: "feature/reset-target", oid: "bbbbbbbb")

    #expect(!ResetBranchTarget.isAvailable(for: main))
    #expect(ResetBranchTarget.isAvailable(for: feature))
  }

  @Test("Sidebar branch tip is passed to the reset sheet")
  func resetSheetUsesSelectedBranchTip() throws {
    let feature = try branch(name: "feature/reset-target", oid: "bbbbbbbb")
    let target = ResetBranchTarget(branch: feature)

    guard case .reset(let tip, let description) = target.resetSheet else {
      Issue.record("Expected reset sheet")
      return
    }

    #expect(tip == feature.tip)
    #expect(description == "branch \"feature/reset-target\"")
  }

  private func branch(
    name: String,
    isCurrent: Bool = false,
    oid: String
  ) throws -> Branch {
    let tip = try #require(ObjectID(rawValue: oid))
    return Branch(
      name: name,
      isCurrent: isCurrent,
      tip: tip,
      subject: "Subject",
      upstream: nil,
      ahead: nil,
      behind: nil,
      committedAt: nil
    )
  }
}
