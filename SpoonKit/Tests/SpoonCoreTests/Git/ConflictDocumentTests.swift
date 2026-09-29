import Testing

@testable import SpoonCore

@Suite("Conflict document")
struct ConflictDocumentTests {
  private let twoConflicts = """
    header
    <<<<<<< HEAD
    ours one
    =======
    theirs one
    >>>>>>> topic
    middle
    <<<<<<< HEAD
    ours two
    ||||||| base
    base two
    =======
    theirs two
    theirs two b
    >>>>>>> topic
    footer

    """

  @Test func splitsTextAndConflictsInFileOrder() throws {
    let document = ConflictDocument(text: twoConflicts)

    #expect(document.blocks.count == 2)
    let first = document.blocks[0]
    #expect(first.index == 0)
    #expect(first.startLine == 2)
    #expect(first.oursLabel == "HEAD")
    #expect(first.theirsLabel == "topic")
    #expect(first.ours == ["ours one\n"])
    #expect(first.theirs == ["theirs one\n"])
    #expect(first.base == nil)

    let second = document.blocks[1]
    #expect(second.index == 1)
    #expect(second.startLine == 8)
    #expect(second.baseLabel == "base")
    #expect(second.base == ["base two\n"])
    #expect(second.theirs == ["theirs two\n", "theirs two b\n"])
    #expect(
      document.outline(context: 3) == [
        .context(["header\n"]), .conflict(first), .context(["middle\n"]), .conflict(second),
        .context(["footer\n"]),
      ])
  }

  @Test func resolvingOneConflictKeepsTheOthersMarkers() {
    let document = ConflictDocument(text: twoConflicts)

    let resolved = document.text(resolving: 0, with: .theirs)

    #expect(resolved.hasPrefix("header\ntheirs one\nmiddle\n<<<<<<< HEAD\n"))
    #expect(ConflictDocument(text: resolved).blocks.map(\.index) == [0])
    #expect(
      document.text(resolving: 1, with: .both).hasSuffix(
        "middle\nours two\ntheirs two\ntheirs two b\nfooter\n"))
  }

  @Test func outlineCountsTheLinesItLeavesOut() {
    let filler = (1...10).map { "line \($0)\n" }.joined()
    let conflict = "<<<<<<< a\nx\n=======\ny\n>>>>>>> b\n"
    let document = ConflictDocument(text: filler + conflict + filler + conflict + "end\n")
    let items = document.outline(context: 3)

    #expect(items.count == 8)
    #expect(items[0] == .omitted(lineCount: 7))
    #expect(items[1] == .context(["line 8\n", "line 9\n", "line 10\n"]))
    #expect(items[3] == .context(["line 1\n", "line 2\n", "line 3\n"]))
    #expect(items[4] == .omitted(lineCount: 4))
    #expect(items[5] == .context(["line 8\n", "line 9\n", "line 10\n"]))
    #expect(items[7] == .context(["end\n"]))
  }

  @Test func unchangedDocumentReproducesTheFileExactly() {
    for text in [twoConflicts, "no newline at end", "", "a\r\nb\r\n", "\n\n"] {
      let document = ConflictDocument(text: text)
      let rebuilt = document.segments.map {
        switch $0 {
        case .text(let lines): lines.joined()
        case .conflict(let block): block.rawLines.joined()
        }
      }.joined()
      #expect(rebuilt == text)
    }
  }

  @Test func onlyExactSevenCharacterMarkersCount() {
    let document = ConflictDocument(
      text: """
        <<<<<<<< eight
        ========
        >>>>>>>>
        <<<<<<< HEAD\r
        ours\r
        =======\r
        theirs\r
        >>>>>>> topic\r
        <<<<<<< never closed
        dangling

        """
    )

    #expect(document.blocks.count == 1)
    #expect(document.blocks[0].ours == ["ours\r\n"])
    #expect(document.blocks[0].theirsLabel == "topic")
    #expect(document.outline(context: 1).last == .omitted(lineCount: 1))
  }
}
