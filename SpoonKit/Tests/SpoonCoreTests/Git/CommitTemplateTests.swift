import Foundation
import Testing

@testable import SpoonCore

@Suite("CommitTemplate")
struct CommitTemplateTests {
  @Test func splitsBodyFromCommentLines() {
    let template = CommitTemplate.parse(
      """
      feat: 

      # Summarize the change in 50 characters or less.
      Refs: #
      #
      # Explain why, not how.


      """, path: ".gitmessage")
    #expect(template.body == "feat: \n\nRefs: #")
    #expect(template.comments == ["Summarize the change in 50 characters or less.", "Explain why, not how."])
  }

  @Test func honorsACustomCommentCharacter() {
    let template = CommitTemplate.parse("; hint\n# not a comment\n", path: "t", commentCharacter: ";")
    #expect(template.body == "# not a comment")
    #expect(template.comments == ["hint"])
  }

  @Test func readsTheConfiguredTemplateRelativeToTheRepository() async throws {
    let runner = SubprocessCommandRunner()
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = LiveRepoFixture.makeClient(for: root, runner: runner)
    #expect(try await client.commitTemplate() == nil)

    try Data("Subject\n\n; Why?\n".utf8).write(to: root.appending(path: ".gitmessage"))
    try await LiveRepoFixture.run(["config", "commit.template", ".gitmessage"], in: root, runner: runner)
    try await LiveRepoFixture.run(["config", "core.commentChar", ";"], in: root, runner: runner)

    #expect(
      try await client.commitTemplate()
        == CommitTemplate(path: ".gitmessage", body: "Subject", comments: ["Why?"]))
  }
}
