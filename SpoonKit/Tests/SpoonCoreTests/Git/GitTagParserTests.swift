import Foundation
import Testing

@testable import SpoonCore

@Suite("GitTagParser")
struct GitTagParserTests {
  @Test func parsesAnnotatedAndLightweightTags() throws {
    let fixture =
      "v2.0.0\u{0}aaaa1111\u{0}bbbb2222\u{0}1720000000\n"
      + "lightweight\u{0}cccc3333\u{0}\u{0}1710000000\n"
    let tags = try GitTagParser.parse(Data(fixture.utf8))
    #expect(tags.count == 2)

    #expect(tags[0].name == "v2.0.0")
    // Annotated tags peel to the tagged commit, not the tag object.
    #expect(tags[0].target.rawValue == "bbbb2222")
    #expect(tags[0].isAnnotated)
    #expect(tags[0].createdAt == Date(timeIntervalSince1970: 1_720_000_000))

    #expect(tags[1].name == "lightweight")
    #expect(tags[1].target.rawValue == "cccc3333")
    #expect(!tags[1].isAnnotated)
  }

  @Test func malformedRecordThrows() {
    #expect(throws: GitTagParser.ParseError.self) {
      try GitTagParser.parse(Data("only-two-fields\u{0}aaaa1111\n".utf8))
    }
  }
}
