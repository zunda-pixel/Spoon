import Foundation
import Testing

@testable import SpoonCore

@Suite("Commit description")
struct CommitDescriptionTests {
  @Test func nearestTagKeepsDashesInTheTagName() throws {
    let plain = try #require(CommitDescription.parseNearest("0.0.9-1-gee69a4e\n"))
    #expect(plain.tag == "0.0.9")
    #expect(plain.distance == 1)
    let dashed = try #require(CommitDescription.parseNearest("release-2026-09-0-gabc1234"))
    #expect(dashed.tag == "release-2026-09")
    #expect(dashed.distance == 0)
    #expect(CommitDescription.parseNearest("  \n") == nil)
  }

  @Test func containingTagDropsTheRevisionPath() {
    #expect(CommitDescription.parseContaining("0.0.10~3\n") == "0.0.10")
    #expect(CommitDescription.parseContaining("v2.0^2~1") == "v2.0")
    #expect(CommitDescription.parseContaining("0.0.11") == "0.0.11")
    #expect(CommitDescription.parseContaining("") == nil)
  }
}
