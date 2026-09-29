import SpoonCore

/// A pending "take one side" resolution awaiting confirmation.
struct ConflictResolutionRequest: Hashable, Identifiable {
  let entry: FileStatusEntry
  let side: FileStatusEntry.ConflictSide

  var id: String { "\(entry.path)|\(side.rawValue)" }
}

extension FileStatusEntry.ConflictSide {
  /// What this side means for the operation in progress. During a rebase,
  /// git's "ours" is the branch being rebased onto and "theirs" is the
  /// commit being replayed, the reverse of a merge.
  func displayName(during kind: SequencerState.Kind?) -> String {
    switch (self, kind) {
    case (.ours, .rebase): "Upstream Version (Ours)"
    case (.theirs, .rebase): "Your Commit’s Version (Theirs)"
    case (.ours, _): "Current Branch Version (Ours)"
    case (.theirs, _): "Incoming Version (Theirs)"
    }
  }
}
