import Testing

@testable import SpoonCore

@Suite("CloneOptions")
struct CloneOptionsTests {
  @Test func standardUsesPlainClone() {
    #expect(CloneOptions.standard.cloneArguments() == ["clone", "--progress"])
  }

  @Test func partialAndShallowCloneArguments() {
    let options = CloneOptions(
      filterBlobNone: true,
      depth: 1,
      singleBranch: true,
      branch: "main",
      recurseSubmodules: true
    )
    #expect(
      options.cloneArguments() == [
        "clone",
        "--progress",
        "--filter=blob:none",
        "--depth=1",
        "--single-branch",
        "--branch",
        "main",
        "--recurse-submodules",
      ]
    )
  }

  @Test func trimsBranchName() {
    let options = CloneOptions(branch: "  develop  ")
    #expect(options.branch == "develop")
    #expect(options.cloneArguments() == ["clone", "--progress", "--branch", "develop"])
  }

  @Test func ignoresZeroDepth() {
    let options = CloneOptions(depth: 0)
    #expect(options.cloneArguments() == ["clone", "--progress"])
  }
}
