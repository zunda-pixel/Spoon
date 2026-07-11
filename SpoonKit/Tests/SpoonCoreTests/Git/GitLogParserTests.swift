import Foundation
import Testing

@testable import SpoonCore

@Suite("GitLogParser")
struct GitLogParserTests {
  private let a = String(repeating: "a", count: 40)
  private let b = String(repeating: "b", count: 40)
  private let c = String(repeating: "c", count: 40)

  private func record(
    oid: String,
    parents: String = "",
    subject: String = "A subject"
  ) -> String {
    [oid, parents, "Alice", "alice@example.com", "1720000000", "1720000100", subject]
      .joined(separator: "\u{1f}")
  }

  @Test func parsesCommitFields() throws {
    let data = Data((record(oid: a, parents: b, subject: "fix: 日本語 subject") + "\0").utf8)
    let commits = try GitLogParser.parse(data)
    let commit = try #require(commits.first)
    #expect(commit.oid.rawValue == a)
    #expect(commit.parents.map(\.rawValue) == [b])
    #expect(commit.authorName == "Alice")
    #expect(commit.authorEmail == "alice@example.com")
    #expect(commit.authoredAt == Date(timeIntervalSince1970: 1_720_000_000))
    #expect(commit.committedAt == Date(timeIntervalSince1970: 1_720_000_100))
    #expect(commit.subject == "fix: 日本語 subject")
    #expect(!commit.isMerge)
  }

  @Test func parsesMergeAndRootCommits() throws {
    let data = Data(
      [
        record(oid: a, parents: "\(b) \(c)", subject: "merge"),
        record(oid: b, parents: "", subject: "root"),
      ].joined(separator: "\0").utf8
    )
    let commits = try GitLogParser.parse(data)
    #expect(commits.count == 2)
    #expect(commits[0].isMerge)
    #expect(commits[0].parents.count == 2)
    #expect(commits[1].parents.isEmpty)
  }

  @Test func subjectMayContainFieldSeparator() throws {
    // maxSplits keeps any stray 0x1F inside the subject.
    let data = Data((record(oid: a, subject: "weird\u{1f}subject") + "\0").utf8)
    let commit = try #require(try GitLogParser.parse(data).first)
    #expect(commit.subject == "weird\u{1f}subject")
  }

  @Test func malformedRecordThrows() {
    #expect(throws: GitLogParser.ParseError.self) {
      try GitLogParser.parse(Data("nonsense".utf8))
    }
  }

  @Test func emptyOutputMeansNoCommits() throws {
    #expect(try GitLogParser.parse(Data()).isEmpty)
  }
}
