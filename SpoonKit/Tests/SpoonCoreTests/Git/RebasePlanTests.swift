import Foundation
import Testing

@testable import SpoonCore

@Suite("RebasePlan")
struct RebasePlanTests {
  private func commit(_ oid: String, _ subject: String) -> Commit {
    Commit(
      oid: ObjectID(rawValue: oid)!,
      parents: [],
      subject: subject,
      authorName: "Tester",
      authorEmail: "tester@example.com",
      authoredAt: Date(timeIntervalSince1970: 0),
      committedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func plan(_ steps: [(RebaseAction, String, String)]) -> RebasePlan {
    RebasePlan(
      steps: steps.map { RebaseStep(action: $0.0, commit: commit($0.1, $0.2)) },
      baseOID: ObjectID(rawValue: "beef0000")
    )
  }

  @Test func todoRendersOldestFirstWithExplicitDrops() {
    let plan = plan([
      (.pick, "aaaa1111", "first"),
      (.drop, "bbbb2222", "second"),
      (.squash, "cccc3333", "third"),
      (.edit, "dddd4444", "fourth"),
    ])
    #expect(
      plan.todoFileContents() == """
        pick aaaa1111 first
        drop bbbb2222 second
        squash cccc3333 third
        edit dddd4444 fourth

        """
    )
  }

  @Test func allPickPlanIsValid() {
    #expect(plan([(.pick, "aaaa1111", "a"), (.pick, "bbbb2222", "b")]).validationError == nil)
  }

  @Test func squashAfterKeptCommitIsValid() {
    #expect(plan([(.edit, "aaaa1111", "a"), (.squash, "bbbb2222", "b")]).validationError == nil)
  }

  @Test func leadingSquashIsInvalid() {
    #expect(
      plan([(.squash, "aaaa1111", "a"), (.pick, "bbbb2222", "b")]).validationError
        == .squashWithoutTarget
    )
  }

  @Test func squashAfterDropOnlyPrefixIsInvalid() {
    #expect(
      plan([(.drop, "aaaa1111", "a"), (.squash, "bbbb2222", "b")]).validationError
        == .squashWithoutTarget
    )
  }

  @Test func allDropPlanIsEmpty() {
    #expect(plan([(.drop, "aaaa1111", "a"), (.drop, "bbbb2222", "b")]).validationError == .empty)
    #expect(RebasePlan(steps: [], baseOID: nil).validationError == .empty)
  }
}
