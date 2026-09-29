import SpoonCore
import SwiftUI

/// Stashes all changes or a selection of files, with the scope options of
/// `git stash push`.
@MainActor
struct StashChangesSheet: View {
  let model: RepositoryModel
  /// Paths to stash; empty stashes every change.
  let paths: [String]
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var scope = StashSaveOptions.Scope.allChanges
  @State private var includeUntracked: Bool

  init(model: RepositoryModel, paths: [String]) {
    self.model = model
    self.paths = paths
    // Selected untracked files would otherwise be silently left behind.
    let untracked = Set(model.status?.untrackedEntries.map(\.path) ?? [])
    self._includeUntracked = State(
      initialValue: paths.isEmpty || paths.contains(where: untracked.contains)
    )
  }

  var body: some View {
    SheetFormLayout(
      title: paths.isEmpty ? "Stash Changes" : "Stash Selected Files",
      subtitle: paths.isEmpty ? nil : summary
    ) {
      Form {
        TextField("Message", text: $message, prompt: Text("Optional"))
        Picker("Stash", selection: $scope) {
          Text("All changes").tag(StashSaveOptions.Scope.allChanges)
          Text("Staged changes only").tag(StashSaveOptions.Scope.stagedOnly)
          Text("All changes, keeping staged ones").tag(StashSaveOptions.Scope.keepingIndex)
        }
        Toggle("Include untracked files", isOn: $includeUntracked)
          .disabled(scope == .stagedOnly)
      }
      .frame(width: 400)
      Text(scopeDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Stash", action: stash)
        .keyboardShortcut(.defaultAction)
        .disabled(model.isBusy || model.isSequencing)
    }
  }

  private var summary: String {
    paths.count == 1 ? paths[0] : "\(paths.count) files"
  }

  private var scopeDescription: String {
    switch scope {
    case .allChanges:
      "Staged and unstaged changes are saved and removed from the working tree."
    case .stagedOnly:
      "Only what is staged is saved; unstaged edits stay in the working tree."
    case .keepingIndex:
      "Everything is saved, but staged changes also stay in place, so you can test or commit them."
    }
  }

  private func stash() {
    let options = StashSaveOptions(
      message: message,
      scope: scope,
      includeUntracked: includeUntracked,
      paths: paths
    )
    dismiss()
    Task { await model.saveStash(options) }
  }
}
