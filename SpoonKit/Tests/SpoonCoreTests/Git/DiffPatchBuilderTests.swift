import Foundation
import Testing

@testable import SpoonCore

@Suite("DiffPatchBuilder")
struct DiffPatchBuilderTests {
  /// Parses a diff, rebuilds a patch from ALL hunks, and expects the
  /// hunk bodies to survive byte-exact.
  @Test func fullSelectionRoundTripsContent() throws {
    let original = """
      diff --git a/file.txt b/file.txt
      --- a/file.txt
      +++ b/file.txt
      @@ -1,3 +1,3 @@
       one
      -two
      +TWO
       three
      @@ -10,2 +10,3 @@
       ten
      +ten-and-a-half
       eleven

      """
    let diff = try #require(try GitDiffParser.parse(Data(original.utf8)).first)
    let patch = try #require(
      DiffPatchBuilder.patch(for: diff, including: Set(diff.hunks.map(\.id)))
    )
    #expect(patch.contains(" one\n-two\n+TWO\n three\n"))
    #expect(patch.contains(" ten\n+ten-and-a-half\n eleven\n"))
    #expect(patch.hasPrefix("diff --git a/file.txt b/file.txt\n--- a/file.txt\n+++ b/file.txt\n"))
    // Full selection keeps git's own numbers.
    #expect(patch.contains("@@ -1,3 +1,3 @@"))
    #expect(patch.contains("@@ -10,2 +10,3 @@"))
  }

  @Test func partialSelectionRecomputesNewStart() throws {
    // First hunk removes one line (delta -1). If only the SECOND hunk is
    // selected, its new-side start must NOT include that delta.
    let original = """
      diff --git a/file.txt b/file.txt
      --- a/file.txt
      +++ b/file.txt
      @@ -1,2 +1,1 @@
       keep
      -drop
      @@ -10,2 +9,3 @@
       ten
      +new
       eleven

      """
    let diff = try #require(try GitDiffParser.parse(Data(original.utf8)).first)
    let second = diff.hunks[1]
    let patch = try #require(DiffPatchBuilder.patch(for: diff, including: [second.id]))
    // Without the first hunk, old and new sides align again.
    #expect(patch.contains("@@ -10,2 +10,3 @@"))
    #expect(!patch.contains("drop"))
  }

  @Test func pureInsertionHunkAnchorsAfterOldStart() throws {
    let original = """
      diff --git a/file.txt b/file.txt
      --- a/file.txt
      +++ b/file.txt
      @@ -5,0 +6,2 @@
      +alpha
      +beta

      """
    let diff = try #require(try GitDiffParser.parse(Data(original.utf8)).first)
    let patch = try #require(
      DiffPatchBuilder.patch(for: diff, including: Set(diff.hunks.map(\.id)))
    )
    #expect(patch.contains("@@ -5,0 +6,2 @@"))
  }

  @Test func noNewlineMarkerSurvivesRebuild() throws {
    let original = """
      diff --git a/x b/x
      --- a/x
      +++ b/x
      @@ -1,1 +1,1 @@
      -old
      +new
      \\ No newline at end of file

      """
    let diff = try #require(try GitDiffParser.parse(Data(original.utf8)).first)
    let patch = try #require(
      DiffPatchBuilder.patch(for: diff, including: Set(diff.hunks.map(\.id)))
    )
    #expect(patch.contains("+new\n\\ No newline at end of file\n"))
  }

  // MARK: - discardPatch

  private var twoChangeDiff: FileDiff {
    get throws {
      let original = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -3,5 +3,5 @@
         three
        -FOUR
        +four
         five
        -SIX
        +six
         seven

        """
      return try #require(try GitDiffParser.parse(Data(original.utf8)).first)
    }
  }

  @Test func discardSelectedAdditionDemotesNothingElse() throws {
    let diff = try twoChangeDiff
    let hunk = diff.hunks[0]
    // Select only the "+four" line (offset 2: [ctx, -FOUR, +four, ...]).
    let patch = try #require(
      DiffPatchBuilder.discardPatch(for: diff, hunkID: hunk.id, selectedOffsets: [2])
    )
    // Unselected -SIX omitted; unselected +six demoted to context.
    #expect(patch.contains("+four\n"))
    #expect(!patch.contains("-FOUR"))
    #expect(!patch.contains("-SIX"))
    #expect(patch.contains(" six\n"))
    // Worktree side: three,four,five,six,seven = 5; result side loses +four = 4.
    #expect(patch.contains("@@ -3,4 +3,5 @@"))
  }

  @Test func discardPairRestoresDeletionAndRemovesAddition() throws {
    let diff = try twoChangeDiff
    let hunk = diff.hunks[0]
    // Select the -FOUR/+four pair (offsets 1 and 2).
    let patch = try #require(
      DiffPatchBuilder.discardPatch(for: diff, hunkID: hunk.id, selectedOffsets: [1, 2])
    )
    #expect(patch.contains("-FOUR\n+four\n"))
    #expect(patch.contains(" six\n"))
    // Both sides count 5: one line swaps back.
    #expect(patch.contains("@@ -3,5 +3,5 @@"))
  }

  @Test func discardSelectionIgnoresContextOffsets() throws {
    let diff = try twoChangeDiff
    let hunk = diff.hunks[0]
    // Offset 0 is context — alone it yields nil; with a change it's ignored.
    #expect(DiffPatchBuilder.discardPatch(for: diff, hunkID: hunk.id, selectedOffsets: [0]) == nil)
    let patch = try #require(
      DiffPatchBuilder.discardPatch(for: diff, hunkID: hunk.id, selectedOffsets: [0, 2])
    )
    #expect(patch.contains("+four\n"))
  }

  @Test func discardRejectsNoNewlineHunksAndNonModified() throws {
    let noNewline = """
      diff --git a/x b/x
      --- a/x
      +++ b/x
      @@ -1,1 +1,1 @@
      -old
      +new
      \\ No newline at end of file

      """
    let diff = try #require(try GitDiffParser.parse(Data(noNewline.utf8)).first)
    let hunk = diff.hunks[0]
    #expect(
      DiffPatchBuilder.discardPatch(for: diff, hunkID: hunk.id, selectedOffsets: [1]) == nil
    )

    var added = try twoChangeDiff
    added.kind = .added
    #expect(
      DiffPatchBuilder.discardPatch(for: added, hunkID: added.hunks[0].id, selectedOffsets: [2])
        == nil
    )
  }

  @Test func changedLineOffsetsSkipsContext() throws {
    let diff = try twoChangeDiff
    #expect(DiffPatchBuilder.changedLineOffsets(of: diff.hunks[0]) == [1, 2, 4, 5])
  }

  @Test func emptySelectionAndBinaryYieldNil() throws {
    let original = """
      diff --git a/x b/x
      --- a/x
      +++ b/x
      @@ -1,1 +1,1 @@
      -a
      +b

      """
    let diff = try #require(try GitDiffParser.parse(Data(original.utf8)).first)
    #expect(DiffPatchBuilder.patch(for: diff, including: []) == nil)

    var binary = diff
    binary.isBinary = true
    #expect(DiffPatchBuilder.patch(for: binary, including: Set(diff.hunks.map(\.id))) == nil)
  }
}
