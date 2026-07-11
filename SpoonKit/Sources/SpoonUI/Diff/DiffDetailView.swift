import SpoonCore
import SwiftUI

/// Detail column for a working-tree file selected in Changes.
@MainActor
struct DiffDetailView: View {
  let model: RepositoryModel
  let selection: RepositoryModel.FileSelection

  @State private var diffs: [FileDiff]?
  @State private var errorMessage: String?

  init(model: RepositoryModel, selection: RepositoryModel.FileSelection) {
    self.model = model
    self.selection = selection
  }

  var body: some View {
    Group {
      if let diffs {
        if diffs.isEmpty {
          ContentUnavailableView(
            "No Changes",
            systemImage: "doc",
            description: Text("This file has no changes in this area anymore.")
          )
        } else {
          FileDiffListView(diffs: diffs, hunkAction: hunkAction)
        }
      } else if let errorMessage {
        ContentUnavailableView(
          "Could Not Load Diff",
          systemImage: "exclamationmark.triangle",
          description: Text(errorMessage)
        )
      } else {
        ProgressView()
      }
    }
    .task(id: taskKey) {
      do {
        errorMessage = nil
        diffs = try await model.diff(for: selection)
      } catch {
        diffs = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  /// Reload when the selected file, its area, or the underlying status
  /// snapshot changes (e.g. after staging from another view).
  private var taskKey: String {
    "\(selection.area)|\(selection.path)|\(model.status.hashValue)"
  }

  /// Hunk-level staging is only well-defined for content edits to
  /// tracked files (see DiffPatchBuilder).
  private var hunkAction: HunkAction? {
    switch selection.area {
    case .unstaged:
      HunkAction(
        title: "Stage Hunk",
        systemImage: "plus.circle",
        isEnabled: { $0.kind == .modified && !$0.isBinary }
      ) { diff, hunk in
        Task { await model.stageHunk(hunk.id, of: diff) }
      }
    case .staged:
      HunkAction(
        title: "Unstage Hunk",
        systemImage: "minus.circle",
        isEnabled: { $0.kind == .modified && !$0.isBinary }
      ) { diff, hunk in
        Task { await model.unstageHunk(hunk.id, of: diff) }
      }
    case .untracked, .conflicted:
      nil
    }
  }
}
