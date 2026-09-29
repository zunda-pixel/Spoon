import Foundation
import Testing

@testable import SpoonCore

@Suite("Line history parsing")
struct LineHistoryParserTests {
  @Test func recordsSplitIntoCommitsAndTheirPatches() throws {
    let a = String(repeating: "a", count: 40)
    let b = String(repeating: "b", count: 40)
    let output = """
      \u{1e}\(a)\u{1f}\(b)\u{1f}Ada\u{1f}ada@example.com\u{1f}1700000100\u{1f}1700000100\u{1f}Rename greeting

      diff --git a/Greeting.swift b/Greeting.swift
      --- a/Greeting.swift
      +++ b/Greeting.swift
      @@ -2,1 +2,1 @@
      -  "Hello"
      +  "Hi"
      \u{1e}\(b)\u{1f}\u{1f}Bo\u{1f}bo@example.com\u{1f}1700000000\u{1f}1700000000\u{1f}Add greeting

      diff --git a/Greeting.swift b/Greeting.swift
      new file mode 100644
      --- /dev/null
      +++ b/Greeting.swift
      @@ -0,0 +2,1 @@
      +  "Hello"

      """

    let entries = try LineHistoryParser.parse(Data(output.utf8))

    #expect(entries.map(\.commit.subject) == ["Rename greeting", "Add greeting"])
    #expect(entries[0].commit.parents.map(\.rawValue) == [b])
    #expect(entries[0].diffs.map(\.path) == ["Greeting.swift"])
    #expect(entries[0].diffs.first?.hunks.count == 1)
    #expect(entries[1].commit.parents.isEmpty)
    #expect(entries[1].diffs.first?.hunks.first?.lines.count == 1)
    #expect(try LineHistoryParser.parse(Data()).isEmpty)
  }
}
