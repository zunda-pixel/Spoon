import Testing

@testable import SpoonCore

@Suite("Submodule parsing")
struct SubmoduleParserTests {
  private let oid = "c299dc4ab4abf689eac6f5bd842503f3e4484cfc"

  @Test func statusLinesCarryStatePathAndDescribe() {
    let submodules = SubmoduleParser.parseStatus(
      """
       \(oid) libs/my lib (heads/master)
      -\(oid) other
      +\(oid) Vendor/Kit (v1.2-3-gabc)
      U\(oid) conflicted
      """
    )

    #expect(submodules.map(\.path) == ["libs/my lib", "other", "Vendor/Kit", "conflicted"])
    #expect(submodules.map(\.state) == [.upToDate, .notInitialized, .differentCommit, .conflicted])
    #expect(submodules.map(\.describe) == ["heads/master", nil, "v1.2-3-gabc", nil])
    #expect(submodules[0].commit.rawValue == oid)
  }

  @Test func gitmodulesMapPathsToNamesAndURLs() {
    let modules = SubmoduleParser.parseModules(
      [
        "submodule.libs/my lib.path\nlibs/my lib",
        "submodule.libs/my lib.url\n../lib",
        "submodule.kit.v2.path\nVendor/Kit",
        "submodule.kit.v2.url\nhttps://example.com/kit.git",
        "submodule.orphan.url\nhttps://example.com/orphan.git",
      ].map { $0 + "\0" }.joined()
    )

    #expect(modules.count == 2)
    #expect(modules["libs/my lib"]?.name == "libs/my lib")
    #expect(modules["libs/my lib"]?.url == "../lib")
    #expect(modules["Vendor/Kit"]?.name == "kit.v2")
    #expect(modules["Vendor/Kit"]?.url == "https://example.com/kit.git")
  }
}
