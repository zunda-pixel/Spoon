import Foundation
import Testing

@testable import SpoonCore

@Suite("GitReflogParser")
struct GitReflogParserTests {
  @Test func parsesEntries() throws {
    let data = Data(
      "aaaa1111\u{1f}HEAD@{0}\u{1f}commit: add feature\u{1f}Taylor\u{1f}t@example.com\u{1f}1720000000\u{0}"
        .utf8
    )

    let entry = try #require(try GitReflogParser.parse(data).first)

    #expect(entry.oid.rawValue == "aaaa1111")
    #expect(entry.selector == "HEAD@{0}")
    #expect(entry.subject == "commit: add feature")
    #expect(entry.authorName == "Taylor")
    #expect(entry.date == Date(timeIntervalSince1970: 1_720_000_000))
  }

  @Test func parsesMultipleEntriesIncludingMultilineSubjects() throws {
    let data = Data(
      """
      aaaa1111\u{1f}HEAD@{0}\u{1f}commit: first line
      second line\u{1f}Taylor\u{1f}t@example.com\u{1f}1720000000\u{0}bbbb2222\u{1f}HEAD@{1}\u{1f}reset: moving to HEAD~1\u{1f}Morgan\u{1f}m@example.com\u{1f}1710000000\u{0}
      """.utf8
    )

    let entries = try GitReflogParser.parse(data)

    #expect(entries.count == 2)
    #expect(entries[0].subject == "commit: first line\nsecond line")
    #expect(entries[1].selector == "HEAD@{1}")
    #expect(entries[1].authorEmail == "m@example.com")
  }

  @Test func emptyInputProducesNoEntries() throws {
    #expect(try GitReflogParser.parse(Data()).isEmpty)
    #expect(try GitReflogParser.parse(Data("\0\0".utf8)).isEmpty)
  }

  @Test(
    arguments: [
      "missing fields",
      "not-an-object\u{1f}HEAD@{0}\u{1f}commit\u{1f}Taylor\u{1f}t@example.com\u{1f}1720000000",
      "aaaa1111\u{1f}HEAD@{0}\u{1f}commit\u{1f}Taylor\u{1f}t@example.com\u{1f}not-a-date",
    ])
  func rejectsMalformedRecords(_ record: String) {
    #expect(throws: GitReflogParser.ParseError.self) {
      try GitReflogParser.parse(Data((record + "\0").utf8))
    }
  }
}
