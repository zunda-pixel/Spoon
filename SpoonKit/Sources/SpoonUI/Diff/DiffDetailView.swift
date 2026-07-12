import SpoonCore
import SwiftUI

/// Detail column for a working-tree file selected in Changes.
@MainActor
struct DiffDetailView: View {
  let model: RepositoryModel
  let selection: RepositoryModel.FileSelection

  @State private var diffs: [FileDiff]?
  @State private var errorMessage: String?
  @State private var lineSelection: DiffLineSelection?
  @State private var pendingDiscard: PendingDiscard?

  private enum PendingDiscard {
    case lines(FileDiff, Hunk.ID, Set<Int>)
    case hunk(FileDiff, Hunk)

    var lineCount: Int {
      switch self {
      case .lines(_, _, let offsets): offsets.count
      case .hunk(_, let hunk): DiffPatchBuilder.changedLineOffsets(of: hunk).count
      }
    }
  }

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
          VStack(spacing: 0) {
            if let lineSelection, supportsLineSelection {
              selectionBar(lineSelection, diffs: diffs)
              Divider()
            }
            FileDiffListView(
              diffs: diffs,
              hunkAction: hunkAction,
              lineSelection: supportsLineSelection ? $lineSelection : nil,
              onDiscardHunk: selection.area == .unstaged
                ? { diff, hunk in pendingDiscard = .hunk(diff, hunk) }
                : nil
            )
          }
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
        lineSelection = nil  // stale offsets after any reload
      } catch {
        diffs = nil
        errorMessage = error.localizedDescription
      }
    }
    .confirmationDialog(
      "Discard \(pendingDiscard?.lineCount ?? 0) changed line(s)?",
      isPresented: .init(
        get: { pendingDiscard != nil },
        set: { if !$0 { pendingDiscard = nil } }
      )
    ) {
      Button("Discard Changes", role: .destructive) {
        confirmPendingDiscard()
      }
    } message: {
      Text("The selected changes will be reverted in the working tree. This cannot be undone.")
    }
  }

  /// Line selection exists where a line-level action does: discard for
  /// unstaged diffs, unstage for staged diffs.
  private var supportsLineSelection: Bool {
    selection.area == .unstaged || selection.area == .staged
  }

  private func selectionBar(_ lineSelection: DiffLineSelection, diffs: [FileDiff]) -> some View {
    LineSelectionBar(selection: lineSelection, onDeselect: { self.lineSelection = nil }) {
      if selection.area == .unstaged {
        Button("Discard Selected Lines…", role: .destructive) {
          guard let diff = diffs.first(where: { $0.id == lineSelection.fileID }) else { return }
          pendingDiscard = .lines(diff, lineSelection.hunkID, lineSelection.offsets)
        }
      } else {
        Button("Unstage Selected Lines") {
          guard let diff = diffs.first(where: { $0.id == lineSelection.fileID }) else { return }
          self.lineSelection = nil
          Task { await model.unstageLines(lineSelection.offsets, of: lineSelection.hunkID, in: diff) }
        }
      }
    }
  }

  private func confirmPendingDiscard() {
    guard let pendingDiscard else { return }
    self.pendingDiscard = nil
    lineSelection = nil
    Task {
      switch pendingDiscard {
      case .lines(let diff, let hunkID, let offsets):
        await model.discardLines(offsets, of: hunkID, in: diff)
      case .hunk(let diff, let hunk):
        await model.discardHunk(hunk.id, of: diff)
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
