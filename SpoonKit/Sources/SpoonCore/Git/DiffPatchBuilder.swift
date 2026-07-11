/// Rebuilds minimal patches from parsed diffs so a subset of hunks can be
/// staged (`git apply --cached`) or unstaged (`… -R`). Pure and
/// round-trip-tested: content lines are reproduced byte-exact; only the
/// new-side start numbers are recomputed to account for unselected hunks.
public enum DiffPatchBuilder {
  /// Builds a patch containing only `hunkIDs`. Returns nil when the
  /// selection is empty or the diff has no applicable hunks.
  ///
  /// Hunk-subset patches are only well-defined for content edits to an
  /// existing file — pass `.modified` diffs; whole-file operations
  /// (add/delete/rename) stage via `git add`/`git rm` instead.
  public static func patch(for diff: FileDiff, including hunkIDs: Set<Hunk.ID>) -> String? {
    let selected = diff.hunks.filter { hunkIDs.contains($0.id) }
    guard !selected.isEmpty, !diff.isBinary else { return nil }

    var text = "diff --git a/\(diff.oldPath ?? diff.path) b/\(diff.path)\n"
    text += "--- a/\(diff.oldPath ?? diff.path)\n"
    text += "+++ b/\(diff.path)\n"

    // With earlier hunks omitted, each selected hunk's new-side start
    // shifts by the net delta of the selected hunks before it.
    var delta = 0
    for hunk in diff.hunks {
      guard hunkIDs.contains(hunk.id) else { continue }
      let newStart = hunk.oldCount == 0
        ? hunk.oldStart + delta + 1  // pure insertion anchors after oldStart
        : hunk.oldStart + delta
      text += "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(newStart),\(hunk.newCount) @@\n"
      for line in hunk.lines {
        switch line.kind {
        case .context:
          text += " \(line.text)\n"
        case .addition:
          text += "+\(line.text)\n"
        case .deletion:
          text += "-\(line.text)\n"
        case .noNewlineMarker:
          text += "\(line.text)\n"
        }
      }
      delta += hunk.newCount - hunk.oldCount
    }
    return text
  }
}
