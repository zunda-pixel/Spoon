import Foundation
import Testing

@testable import SpoonCore

@Suite("Contributor")
struct ContributorTests {
  @Test func parsesShortlogSummaryWithEmails() {
    let output = """
         12\tAda Lovelace <ada@example.com>
          3\tGrace <Hopper> <grace@example.com>
          1\tNo Email
      """
    #expect(
      Contributor.parse(output) == [
        Contributor(name: "Ada Lovelace", email: "ada@example.com", commitCount: 12),
        Contributor(name: "Grace <Hopper>", email: "grace@example.com", commitCount: 3),
        Contributor(name: "No Email", email: "", commitCount: 1),
      ])
  }
}
