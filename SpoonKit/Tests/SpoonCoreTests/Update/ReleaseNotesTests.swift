import Testing

@testable import SpoonCore

@Suite("Release notes")
struct ReleaseNotesTests {
  @Test func githubGeneratedNotesSplitIntoHeadingsBulletsAndParagraphs() {
    let notes = """
      ## What's Changed
      * Recognize squash-merged branches by @zunda-pixel in https://github.com/o/r/pull/41
      * Another change


      **Full Changelog**: https://github.com/o/r/compare/0.0.6...0.0.7
      """

    #expect(
      ReleaseNotes.blocks(from: notes) == [
        .heading(level: 2, text: "What's Changed"),
        .bullet(
          "Recognize squash-merged branches by @zunda-pixel in https://github.com/o/r/pull/41"),
        .bullet("Another change"),
        .paragraph("**Full Changelog**: https://github.com/o/r/compare/0.0.6...0.0.7"),
      ]
    )
  }

  @Test func wrappedParagraphLinesJoinAndHashtagsStayText() {
    #expect(
      ReleaseNotes.blocks(from: "First line\nsecond line\n\n#42 is fixed") == [
        .paragraph("First line second line"),
        .paragraph("#42 is fixed"),
      ]
    )
    #expect(ReleaseNotes.blocks(from: "").isEmpty)
  }
}
