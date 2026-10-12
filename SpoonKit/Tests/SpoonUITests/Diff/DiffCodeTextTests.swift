import AppKit
import SpoonCore
import Testing

@testable import SpoonUI

@MainActor
@Suite("Diff code text")
struct DiffCodeTextTests {
  private let lines = [
    DiffLine(kind: .context, text: "let greeting = \"hi\"", oldLine: 1, newLine: 1),
    DiffLine(kind: .deletion, text: "print(\"こんにちは 👋\")", oldLine: 2),
    DiffLine(kind: .addition, text: "print(\"こんばんは 👋\")", newLine: 2),
    DiffLine(kind: .context, text: "", oldLine: 3, newLine: 3),
  ]

  @Test func copiesCodeWithoutMarkersOrLineNumbers() {
    let view = DiffCodeTextView()
    view.show(.init(lines: lines, changedRanges: [:]))

    #expect(
      view.string == "let greeting = \"hi\"\nprint(\"こんにちは 👋\")\nprint(\"こんばんは 👋\")\n")
    #expect(view.isSelectable)
    #expect(!view.isEditable)
  }

  @Test func rowsMatchTheGutterHeight() {
    let view = DiffCodeTextView()
    view.show(.init(lines: lines, changedRanges: [:]))

    #expect(view.contentSize.height == DiffTextMetrics.rowHeight * 4)
    #expect(view.contentSize.width > 0)
  }

  @Test func highlightsChangedCharactersPastWideCharacters() throws {
    let view = DiffCodeTextView()
    // "こん[ばん]は" — Characters 9..<11 of the added line.
    view.show(.init(lines: lines, changedRanges: [2: [9..<11]]))

    let string = view.string as NSString
    let lineStart = string.range(of: "print(\"こんばんは").location
    let text = view.attributedString()
    let highlighted = try #require(
      unsafe text.attribute(.backgroundColor, at: lineStart + 9, effectiveRange: nil) as? NSColor)
    #expect(highlighted.alphaComponent > 0)
    #expect(unsafe text.attribute(.backgroundColor, at: lineStart + 8, effectiveRange: nil) == nil)
  }

  @Test func redrawingTheSameLinesKeepsTheSelection() {
    let view = DiffCodeTextView()
    let content = DiffCodeTextView.Content(lines: lines, changedRanges: [:])
    view.show(content)
    view.setSelectedRange(NSRange(location: 4, length: 20))

    view.show(content)

    #expect(view.selectedRange() == NSRange(location: 4, length: 20))
  }
}
