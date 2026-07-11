import SpoonCore
import SwiftUI

@MainActor
struct ChangesView: View {
  let model: RepositoryModel
  @Binding var selection: RepositoryModel.FileSelection?

  init(model: RepositoryModel, selection: Binding<RepositoryModel.FileSelection?>) {
    self.model = model
    self._selection = selection
  }

  @State private var confirmingDiscard: RepositoryModel.FileSelection?

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if let status = model.status {
          if status.isClean {
            ContentUnavailableView(
              "No Changes",
              systemImage: "checkmark.circle",
              description: Text("The working tree is clean.")
            )
          } else {
            changeList(status)
          }
        } else if let message = model.lastErrorMessage {
          ContentUnavailableView(
            "Could Not Read Status",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
          )
        } else {
          ProgressView()
            .frame(maxHeight: .infinity)
        }
      }
      Divider()
      CommitComposerView(model: model)
    }
    .navigationTitle("Changes")
    .confirmationDialog(
      confirmingDiscard?.area == .untracked
        ? "Delete \(confirmingDiscard?.path ?? "")?"
        : "Discard changes to \(confirmingDiscard?.path ?? "")?",
      isPresented: .init(
        get: { confirmingDiscard != nil },
        set: { if !$0 { confirmingDiscard = nil } }
      )
    ) {
      Button(
        confirmingDiscard?.area == .untracked ? "Delete File" : "Discard Changes",
        role: .destructive
      ) {
        guard let target = confirmingDiscard else { return }
        Task {
          if target.area == .untracked {
            await model.deleteUntracked(paths: [target.path])
          } else {
            await model.discardWorkingTree(paths: [target.path])
          }
        }
      }
    } message: {
      Text("This cannot be undone.")
    }
  }

  private func changeList(_ status: WorkingTreeStatus) -> some View {
    List(selection: $selection) {
      section("Conflicts", entries: status.conflictedEntries, area: .conflicted)
      section("Staged", entries: status.stagedEntries, area: .staged)
      section("Modified", entries: status.unstagedEntries, area: .unstaged)
      section("Untracked", entries: status.untrackedEntries, area: .untracked)
    }
  }

  @ViewBuilder
  private func section(
    _ title: String,
    entries: [FileStatusEntry],
    area: RepositoryModel.ChangeArea
  ) -> some View {
    if !entries.isEmpty {
      Section(title) {
        ForEach(entries) { entry in
          FileStatusRow(entry: entry)
            .tag(RepositoryModel.FileSelection(path: entry.path, area: area))
            .contextMenu {
              contextMenu(for: entry, area: area)
            }
        }
      }
    }
  }

  @ViewBuilder
  private func contextMenu(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) -> some View {
    switch area {
    case .staged:
      Button("Unstage") {
        Task { await model.unstage(paths: [entry.path]) }
      }
    case .unstaged:
      Button("Stage") {
        Task { await model.stage(paths: [entry.path]) }
      }
      Button("Discard Changes…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .untracked:
      Button("Stage") {
        Task { await model.stage(paths: [entry.path]) }
      }
      Button("Delete File…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .conflicted:
      Button("Mark Resolved (Stage)") {
        Task { await model.stage(paths: [entry.path]) }
      }
    }
  }
}

@MainActor
struct FileStatusRow: View {
  let entry: FileStatusEntry

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.path)
          .lineLimit(1)
          .truncationMode(.middle)
        if let originalPath = entry.originalPath {
          Text("from \(originalPath)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    } icon: {
      statusIcon
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    if entry.conflict != nil {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    } else if entry.isUntracked {
      Image(systemName: "questionmark.circle")
        .foregroundStyle(.secondary)
    } else {
      switch entry.staged ?? entry.unstaged {
      case .added:
        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
      case .deleted:
        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
      case .renamed, .copied:
        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue)
      case .modified, .typeChanged, nil:
        Image(systemName: "pencil.circle.fill").foregroundStyle(.yellow)
      }
    }
  }
}
