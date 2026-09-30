import Testing

@testable import SpoonCore

@Suite("Ignore rules")
struct IgnoreRuleTests {
  @Test func parsesMatchedAndUnmatchedRecords() {
    let rules = IgnoreRule.parse(
      ".gitignore\u{0}1\u{0}build/\u{0}build/\u{0}"
        + "sub/.gitignore\u{0}2\u{0}!keep.log\u{0}sub/keep.log\u{0}"
        + "\u{0}\u{0}\u{0}notes.txt\u{0}"
    )

    #expect(rules.count == 3)
    #expect(rules["build/"] == .some(IgnoreRule(source: ".gitignore", line: 1, pattern: "build/")))
    #expect(rules["sub/keep.log"]??.reincludes == true)
    #expect(rules["notes.txt"] == .some(nil))
    #expect(IgnoreRule.parse("").isEmpty)
  }
}
