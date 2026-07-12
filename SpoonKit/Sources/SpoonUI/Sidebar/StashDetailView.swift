import SpoonCore
import SwiftUI

/// Content column for a selected stash: its diff plus apply/pop/drop actions.
@MainActor
struct StashDetailView: View {
  let model: RepositoryModel
  let stashIndex: Int
  @State private var diffs: [FileDiff]?
  @State private var loadErrorMessage: String?
  @State private var confirmingDrop = false

  init(model: RepositoryModel, stashIndex: Int) {
    self.model = model
    self.stashIndex = stashIndex
  }

  private var stash: Stash? {
    model.stashes.first { $0.index == stashIndex }
  }

  var body: some View {
    if let stash {
      VStack(spacing: 0) {
        header(stash)
        Divider()
        content
      }
      // Keyed on the stash value: index shifts after drops still reload,
      // unrelated stack changes don't.
      .task(id: stash) {
        await load(stash)
      }
      .confirmationDialog(
        "Drop \(stash.reference)?",
        isPresented: $confirmingDrop
      ) {
        Button("Drop Stash", role: .destructive) {
          Task { await model.dropStash(stash) }
        }
      } message: {
        Text("The stashed changes will be permanently deleted.")
      }
    } else {
      ContentUnavailableView(
        "Stash Not Found",
        systemImage: "tray",
        description: Text("This stash no longer exists.")
      )
    }
  }

  private func header(_ stash: Stash) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "tray")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(stash.message)
          .lineLimit(2)
        Text(stash.reference)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Apply") {
        Task { await model.applyStash(stash, pop: false) }
      }
      Button("Pop") {
        Task { await model.applyStash(stash, pop: true) }
      }
      Button("Drop…", role: .destructive) {
        confirmingDrop = true
      }
    }
    .disabled(model.isBusy)
    .padding(12)
  }

  @ViewBuilder
  private var content: some View {
    if let diffs {
      if diffs.isEmpty {
        ContentUnavailableView("Empty Stash", systemImage: "tray")
      } else {
        FileDiffListView(diffs: diffs)
      }
    } else if let loadErrorMessage {
      ContentUnavailableView(
        "Could Not Load Stash",
        systemImage: "exclamationmark.triangle",
        description: Text(loadErrorMessage)
      )
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func load(_ stash: Stash) async {
    do {
      diffs = try await model.stashDiffs(stash)
      loadErrorMessage = nil
    } catch {
      diffs = nil
      loadErrorMessage = error.localizedDescription
    }
  }
}
