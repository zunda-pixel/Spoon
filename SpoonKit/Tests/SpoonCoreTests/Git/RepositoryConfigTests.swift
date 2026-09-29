import Foundation
import Testing

@testable import SpoonCore

@Suite("Repository config")
struct RepositoryConfigTests {
  @Test func parsesScopedRecordsAndPrefersLocalValues() {
    let entries = GitConfigEntry.parse(
      "global\0user.name\nAda\0system\0pull.rebase\nfalse\0global\0pull.rebase\ntrue\0local\0user.name\nAda L.\0local\0fetch.prune\0"
    )
    let config = RepositoryConfig(entries: entries)

    #expect(entries.count == 5)
    #expect(config.localValue(.userName) == "Ada L.")
    #expect(config.inheritedValue(.userName)?.value == "Ada")
    #expect(config.inheritedValue(.userName)?.scope == "global")
    #expect(config.localValue(.pullRebase) == nil)
    // The later (more specific) inherited file wins, as in git.
    #expect(config.inheritedValue(.pullRebase)?.value == "true")
    #expect(config.localValue(.fetchPrune) == "true")
    #expect(config.localValue(.commitSign) == nil)
  }

  @Test func patternMatchesEveryEditedKeyLowercased() throws {
    let regex = try NSRegularExpression(pattern: RepositorySetting.pattern)
    for setting in RepositorySetting.allCases {
      let key = setting.rawValue.lowercased()
      #expect(regex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil)
    }
    let other = "user.nameX"
    #expect(regex.firstMatch(in: other, range: NSRange(other.startIndex..., in: other)) == nil)
  }
}
