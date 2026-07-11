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
