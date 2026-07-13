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
}
