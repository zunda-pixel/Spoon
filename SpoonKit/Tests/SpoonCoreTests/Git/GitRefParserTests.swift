import Foundation
import Testing

@testable import SpoonCore

@Suite("GitRefParser")
struct GitRefParserTests {
  private let oid = "4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331"

  private func line(
    head: String = "",
    name: String,
    subject: String = "A subject",
    upstream: String = "",
    track: String = "",
    date: String = "1720000000"
  ) -> String {
    [head, name, oid, subject, upstream, track, date].joined(separator: "\0")
  }

  @Test func parsesCurrentBranchWithTracking() throws {
    let data = Data(
      [
        line(head: "*", name: "main", upstream: "origin/main", track: "[ahead 2, behind 1]"),
        line(name: "feature/login", upstream: "origin/feature/login", track: ""),
      ].joined(separator: "\n").utf8
    )
    let branches = try GitRefParser.parseBranches(data)
    #expect(branches.count == 2)

    let main = branches[0]
    #expect(main.name == "main")
    #expect(main.isCurrent)
    #expect(main.tip.rawValue == oid)
    #expect(main.upstream == "origin/main")
    #expect(main.upstreamRemoteName == "origin")
    #expect(main.ahead == 2)
    #expect(main.behind == 1)
    #expect(main.committedAt == Date(timeIntervalSince1970: 1_720_000_000))

    let feature = branches[1]
    #expect(!feature.isCurrent)
    #expect(feature.ahead == nil)
    #expect(feature.behind == nil)
    #expect(!feature.upstreamGone)
  }

  @Test(arguments: [
    ("[ahead 3]", 3, nil as Int?, false),
    ("[behind 7]", nil as Int?, 7, false),
    ("[gone]", nil as Int?, nil as Int?, true),
    ("", nil as Int?, nil as Int?, false),
  ])
  func trackingVariants(track: String, ahead: Int?, behind: Int?, gone: Bool) throws {
    let data = Data(line(name: "b", upstream: track.isEmpty ? "" : "origin/b", track: track).utf8)
    let branch = try #require(try GitRefParser.parseBranches(data).first)
    #expect(branch.ahead == ahead)
    #expect(branch.behind == behind)
    #expect(branch.upstreamGone == gone)
  }

  @Test func noUpstreamIsNil() throws {
    let data = Data(line(name: "local-only").utf8)
    let branch = try #require(try GitRefParser.parseBranches(data).first)
    #expect(branch.upstream == nil)
    #expect(branch.upstreamRemoteName == nil)
  }

  @Test func slashesInBranchAndUpstreamNames() throws {
    let data = Data(line(name: "user/nested/branch", upstream: "origin/user/nested/branch").utf8)
    let branch = try #require(try GitRefParser.parseBranches(data).first)
    #expect(branch.name == "user/nested/branch")
    #expect(branch.upstreamRemoteName == "origin")
  }

  @Test func malformedLineThrows() {
    #expect(throws: GitRefParser.ParseError.self) {
      try GitRefParser.parseBranches(Data("not enough fields".utf8))
    }
  }

  @Test func emptyOutputMeansNoBranches() throws {
    #expect(try GitRefParser.parseBranches(Data()).isEmpty)
  }
}
