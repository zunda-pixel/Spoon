import Foundation
import Testing

@testable import SpoonCore

@Suite("Code search")
struct CodeSearchTests {
  @Test func queryBecomesGrepArguments() {
    #expect(
      CodeSearchQuery(pattern: "greet").arguments == [
        "grep", "-z", "--line-number", "--column", "-I", "--no-color", "--full-name",
        "--max-count=200", "--ignore-case", "--fixed-strings", "-e", "greet", "--",
      ])
    #expect(
      CodeSearchQuery(
        pattern: "gr(e+)t", revision: "v1.0", matchesCase: true, matchesWholeWord: true,
        syntax: .regularExpression, includesUntracked: true, paths: ["*.swift"]
      ).arguments.suffix(7) == [
        "--word-regexp", "--extended-regexp", "-e", "gr(e+)t", "v1.0", "--", "*.swift",
      ])
    #expect(
      CodeSearchQuery(pattern: "x", includesUntracked: true).arguments.contains("--untracked"))
  }

  @Test func parsesRecordsStripsTheRevisionAndStopsAtTheLimit() {
    let output = Data(
      "v1:Sources/A.swift\u{0}3\u{0}5\u{0}let greet = 1\r\nv1:B.txt\u{0}10\u{0}1\u{0}greet: a\u{0}b\nv1:B.txt\u{0}12\u{0}2\u{0} greet\n"
        .utf8)

    let result = CodeSearchResult.parse(output, revision: "v1", limit: 2)

    #expect(result.isTruncated)
    #expect(
      result.matches == [
        CodeSearchMatch(path: "Sources/A.swift", lineNumber: 3, column: 5, text: "let greet = 1"),
        CodeSearchMatch(path: "B.txt", lineNumber: 10, column: 1, text: "greet: a\u{0}b"),
      ])
    let all = CodeSearchResult.parse(output, revision: "v1", limit: 10)
    #expect(!all.isTruncated)
    #expect(all.files.map(\.path) == ["Sources/A.swift", "B.txt"])
    #expect(all.files.map(\.matches.count) == [1, 2])
  }

  @Test func matchRangesFollowCaseWordAndSyntax() {
    func highlighted(_ query: CodeSearchQuery, in text: String) -> [String] {
      query.matchRanges(in: text).map { String(text[$0]) }
    }
    let text = "Greet greeting greet(a.b)"
    #expect(highlighted(CodeSearchQuery(pattern: "greet"), in: text) == ["Greet", "greet", "greet"])
    #expect(
      highlighted(CodeSearchQuery(pattern: "greet", matchesCase: true), in: text) == [
        "greet", "greet",
      ])
    #expect(
      highlighted(CodeSearchQuery(pattern: "greet", matchesWholeWord: true), in: text) == [
        "Greet", "greet",
      ])
    #expect(highlighted(CodeSearchQuery(pattern: "a.b"), in: "axb a.b") == ["a.b"])
    #expect(
      highlighted(CodeSearchQuery(pattern: "a.b", syntax: .regularExpression), in: "axb") == [
        "axb"
      ])
    #expect(highlighted(CodeSearchQuery(pattern: "(", syntax: .regularExpression), in: "(").isEmpty)
  }
}
