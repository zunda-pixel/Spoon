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
      let newStart =
        hunk.oldCount == 0
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

  /// Builds a patch that removes only the selected changed lines from the
  /// working tree when applied with `git apply -R` (no `--cached`).
  ///
  /// The synthetic hunk's new side must match the current worktree exactly,
  /// so unselected additions demote to context (they exist and stay) and
  /// unselected deletions are omitted (absent and staying absent).
  ///
  /// `selectedOffsets` are indices into `hunk.lines`; only `.addition` and
  /// `.deletion` offsets count. Returns nil for empty/invalid selections,
  /// binary or non-`.modified` diffs, and hunks containing
  /// `\ No newline` markers (end-of-file reverse-apply is too error-prone).
  public static func discardPatch(
    for diff: FileDiff,
    hunkID: Hunk.ID,
    selectedOffsets: Set<Int>
  ) -> String? {
    guard
      !diff.isBinary,
      diff.kind == .modified,
      let hunk = diff.hunks.first(where: { $0.id == hunkID }),
      !hunk.lines.contains(where: { $0.kind == .noNewlineMarker })
    else { return nil }

    let selection = selectedOffsets.filter { offset in
      hunk.lines.indices.contains(offset) && hunk.lines[offset].kind != .context
    }
    guard !selection.isEmpty else { return nil }

    var body = ""
    var resultCount = 0  // a side: worktree after the discard
    var worktreeCount = 0  // b side: worktree as it is now (matched by -R)
    for (offset, line) in hunk.lines.enumerated() {
      switch line.kind {
      case .context:
        body += " \(line.text)\n"
        resultCount += 1
        worktreeCount += 1
      case .addition:
        if selection.contains(offset) {
          body += "+\(line.text)\n"
          worktreeCount += 1
        } else {
          body += " \(line.text)\n"
          resultCount += 1
          worktreeCount += 1
        }
      case .deletion:
        if selection.contains(offset) {
          body += "-\(line.text)\n"
          resultCount += 1
        }
      case .noNewlineMarker:
        return nil  // unreachable (guarded above)
      }
    }

    var text = "diff --git a/\(diff.path) b/\(diff.path)\n"
    text += "--- a/\(diff.path)\n"
    text += "+++ b/\(diff.path)\n"
    text += "@@ -\(hunk.newStart),\(resultCount) +\(hunk.newStart),\(worktreeCount) @@\n"
    text += body
    return text
  }

  /// All selectable (changed) line offsets of a hunk — the "discard whole
  /// hunk" selection.
  public static func changedLineOffsets(of hunk: Hunk) -> Set<Int> {
    Set(
      hunk.lines.indices.filter {
        hunk.lines[$0].kind == .addition || hunk.lines[$0].kind == .deletion
      }
    )
  }
}
