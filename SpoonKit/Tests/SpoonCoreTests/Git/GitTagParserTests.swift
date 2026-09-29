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

  @Test func signatureFieldMarksSignedTags() throws {
    let signed = try GitTagParser.parse(
      Data(
        "v2\u{0}\(String(repeating: "b", count: 40))\u{0}\(String(repeating: "c", count: 40))\u{0}1720000000\u{0}1\nv1\u{0}\(String(repeating: "d", count: 40))\u{0}\u{0}1710000000\u{0}\n"
          .utf8))
    #expect(signed.map(\.isSigned) == [true, false])
    #expect(signed.map(\.isAnnotated) == [true, false])
  }

  @Test func malformedRecordThrows() {
    #expect(throws: GitTagParser.ParseError.self) {
      try GitTagParser.parse(Data("only-two-fields\u{0}aaaa1111\n".utf8))
    }
  }
}
