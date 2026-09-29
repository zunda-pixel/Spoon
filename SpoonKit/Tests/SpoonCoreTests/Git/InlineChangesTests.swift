import Testing

@testable import SpoonCore

@Suite("Inline word changes")
struct InlineChangesTests {
  private func hunk(_ lines: [(DiffLine.Kind, String)]) -> Hunk {
    Hunk(
      header: "@@ -1 +1 @@", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1,
      lines: lines.map { DiffLine(kind: $0.0, text: $0.1) }
    )
  }

  private func text(_ string: String, _ ranges: [Range<Int>]) -> [String] {
    let characters = Array(string)
    return ranges.map { String(characters[$0]) }
  }

  @Test func pairedLinesHighlightOnlyTheChangedWords() {
    let old = "let greeting = \"Hello\""
    let new = "let greeting = \"Hello, world\""
    let ranges = InlineChanges.ranges(in: hunk([(.deletion, old), (.addition, new)]))

    #expect(ranges[0].map { text(old, $0) } == [])
    #expect(ranges[1].map { text(new, $0) } == [", world"])
  }

  @Test func renamesAreMarkedOnBothSides() {
    let old = "func greet(name: String) {"
    let new = "func greet(person: String) {"
    let ranges = InlineChanges.ranges(in: hunk([(.deletion, old), (.addition, new)]))

    #expect(ranges[0].map { text(old, $0) } == ["name"])
    #expect(ranges[1].map { text(new, $0) } == ["person"])
  }

  @Test func unrelatedOrUnpairedLinesAreLeftAlone() {
    let ranges = InlineChanges.ranges(
      in: hunk([
        (.context, "a"),
        (.deletion, "completely"),
        (.addition, "different"),
        (.addition, "extra line"),
      ]))

    #expect(ranges.isEmpty)
  }
}
