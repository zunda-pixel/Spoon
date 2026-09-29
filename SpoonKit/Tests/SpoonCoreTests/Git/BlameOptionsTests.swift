import Testing

@testable import SpoonCore

@Suite("Blame options")
struct BlameOptionsTests {
  private let oid = ObjectID(rawValue: String(repeating: "a", count: 40))!

  @Test func optionsBecomeIgnoreFlags() {
    #expect(BlameOptions().arguments.isEmpty)
    #expect(BlameOptions(skipsListedCommits: false).arguments == ["--ignore-revs-file="])
    #expect(
      BlameOptions(ignoreRevsFile: ".git-blame-ignore-revs", ignoredRevisions: [oid]).arguments
        == ["--ignore-revs-file", ".git-blame-ignore-revs", "--ignore-rev", oid.rawValue])
    // Turning the list off still honors commits picked by hand.
    #expect(
      BlameOptions(skipsListedCommits: false, ignoreRevsFile: "x", ignoredRevisions: [oid])
        .arguments == ["--ignore-revs-file=", "--ignore-rev", oid.rawValue])
  }

  @Test func settingsPassTheConventionalFileOnlyWhenNothingIsConfigured() {
    let conventional = BlameIgnoreSettings(hasConventionalFile: true)
    #expect(conventional.hasList)
    #expect(
      conventional.options(skippingListedCommits: true, ignoring: []).ignoreRevsFile
        == ".git-blame-ignore-revs")
    let configured = BlameIgnoreSettings(configuredFiles: ["tools/ignore"], hasConventionalFile: true)
    #expect(configured.options(skippingListedCommits: true, ignoring: []).ignoreRevsFile == nil)
    #expect(configured.listFileForAdding == "tools/ignore")
    #expect(!BlameIgnoreSettings().hasList)
    #expect(BlameIgnoreSettings().listFileForAdding == ".git-blame-ignore-revs")
  }
}
