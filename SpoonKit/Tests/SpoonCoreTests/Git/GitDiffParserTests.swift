import Foundation
import Testing

@testable import SpoonCore

@Suite("GitDiffParser")
struct GitDiffParserTests {
  private func parse(_ text: String) throws -> [FileDiff] {
    try GitDiffParser.parse(Data(text.utf8))
  }

  @Test func modifiedFileWithOneHunk() throws {
    let diffs = try parse(
      """
      diff --git a/src/main.swift b/src/main.swift
      index e69de29..8b13789 100644
      --- a/src/main.swift
      +++ b/src/main.swift
      @@ -1,3 +1,4 @@ func main() {
       let a = 1
      -let b = 2
      +let b = 3
      +let c = 4
       print(a)

      """
    )
    let diff = try #require(diffs.first)
    #expect(diffs.count == 1)
    #expect(diff.path == "src/main.swift")
    #expect(diff.kind == .modified)
    #expect(diff.hunks.count == 1)

    let hunk = diff.hunks[0]
    #expect(hunk.oldStart == 1)
    #expect(hunk.oldCount == 3)
    #expect(hunk.newStart == 1)
    #expect(hunk.newCount == 4)
    #expect(hunk.header == "@@ -1,3 +1,4 @@ func main() {")
    #expect(hunk.lines.map(\.kind) == [.context, .deletion, .addition, .addition, .context])
    // Line numbers advance independently per side.
    #expect(hunk.lines[1].oldLine == 2)
    #expect(hunk.lines[1].newLine == nil)
    #expect(hunk.lines[2].newLine == 2)
    #expect(hunk.lines[4].oldLine == 3)
    #expect(hunk.lines[4].newLine == 4)
    #expect(diff.additionCount == 2)
    #expect(diff.deletionCount == 1)
  }

  @Test func deletionLineFollowedByNextFileHeaderIsNotConfused() throws {
    // The second file's `--- a/…` must not be eaten as a deletion of the
    // first file's hunk — counts, not prefixes, delimit hunks.
    let diffs = try parse(
      """
      diff --git a/one.txt b/one.txt
      --- a/one.txt
      +++ b/one.txt
      @@ -1,1 +1,1 @@
      -old
      +new
      diff --git a/two.txt b/two.txt
      --- a/two.txt
      +++ b/two.txt
      @@ -1,1 +1,1 @@
      -foo
      +bar

      """
    )
    #expect(diffs.count == 2)
    #expect(diffs[0].hunks[0].lines.count == 2)
    #expect(diffs[1].path == "two.txt")
    #expect(diffs[1].hunks[0].lines.map(\.text) == ["foo", "bar"])
  }

  @Test func newFileAndDeletedFile() throws {
    let diffs = try parse(
      """
      diff --git a/added.txt b/added.txt
      new file mode 100644
      index 0000000..8b13789
      --- /dev/null
      +++ b/added.txt
      @@ -0,0 +1,2 @@
      +hello
      +world
      diff --git a/removed.txt b/removed.txt
      deleted file mode 100644
      index 8b13789..0000000
      --- a/removed.txt
      +++ /dev/null
      @@ -1,1 +0,0 @@
      -goodbye

      """
    )
    #expect(diffs[0].kind == .added)
    #expect(diffs[0].path == "added.txt")
    #expect(diffs[0].newMode == "100644")
    #expect(diffs[1].kind == .deleted)
    #expect(diffs[1].path == "removed.txt")
  }

  @Test func renameWithSpacesInPaths() throws {
    let diffs = try parse(
      """
      diff --git a/old name.txt b/new name.txt
      similarity index 90%
      rename from old name.txt
      rename to new name.txt
      index e69de29..8b13789 100644
      --- a/old name.txt
      +++ b/new name.txt
      @@ -1,1 +1,1 @@
      -a
      +b

      """
    )
    let diff = try #require(diffs.first)
    #expect(diff.kind == .renamed)
    #expect(diff.path == "new name.txt")
    #expect(diff.oldPath == "old name.txt")
  }

  @Test func noNewlineMarkersSurvive() throws {
    let diffs = try parse(
      """
      diff --git a/x.txt b/x.txt
      --- a/x.txt
      +++ b/x.txt
      @@ -1,1 +1,1 @@
      -old
      \\ No newline at end of file
      +new
      \\ No newline at end of file

      """
    )
    let lines = try #require(diffs.first?.hunks.first?.lines)
    #expect(lines.map(\.kind) == [.deletion, .noNewlineMarker, .addition, .noNewlineMarker])
    #expect(lines[1].text == "\\ No newline at end of file")
  }

  @Test func binaryFile() throws {
    let diffs = try parse(
      """
      diff --git a/image.png b/image.png
      index 1234567..89abcde 100644
      Binary files a/image.png and b/image.png differ

      """
    )
    let diff = try #require(diffs.first)
    #expect(diff.isBinary)
    #expect(diff.hunks.isEmpty)
  }

  @Test func modeChangeOnly() throws {
    let diffs = try parse(
      """
      diff --git a/script.sh b/script.sh
      old mode 100644
      new mode 100755

      """
    )
    let diff = try #require(diffs.first)
    #expect(diff.kind == .modified)
    #expect(diff.oldMode == "100644")
    #expect(diff.newMode == "100755")
    #expect(diff.hunks.isEmpty)
    // The `diff --git` line is the only path source for metadata-only
    // changes; `--- / +++` never appear. Path stays resolvable via header
    // fallback in a later milestone — for now it may be empty.
  }

  @Test func countlessHunkHeaderDefaultsToOne() throws {
    let diffs = try parse(
      """
      diff --git a/x b/x
      --- a/x
      +++ b/x
      @@ -1 +1 @@
      -a
      +b

      """
    )
    let hunk = try #require(diffs.first?.hunks.first)
    #expect(hunk.oldCount == 1)
    #expect(hunk.newCount == 1)
  }

  @Test func diffTreePreambleIsSkipped() throws {
    let diffs = try parse(
      """
      4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331
      diff --git a/x b/x
      --- a/x
      +++ b/x
      @@ -1 +1 @@
      -a
      +b

      """
    )
    #expect(diffs.count == 1)
  }

  @Test func emptyInputYieldsNoFiles() throws {
    #expect(try parse("").isEmpty)
  }
}
