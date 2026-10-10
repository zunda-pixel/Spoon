import SpoonCore
import SwiftUI

/// Content column for a selected stash: its diff plus apply/pop/drop actions.
@MainActor
struct StashDetailView: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let stashIndex: Int
  @State private var diffs: [FileDiff]?
  /// Which stash `diffs` belongs to, so another stash's diff never stands
  /// in while the selected one loads.
  @State private var loadedStash: Stash?
  @State private var loadErrorMessage: String?
  @State private var confirmingDrop = false

  init(model: RepositoryModel, navigation: RepositoryNavigationState, stashIndex: Int) {
    self.model = model
    self.navigation = navigation
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
        if loadedStash == stash {
          content
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    AdaptiveActionsLayout(spacing: 10) {
      title(stash)
      WrappingLayout { actions(stash) }
    }
    .disabled(model.isBusy)
    .padding(12)
  }

  private func title(_ stash: Stash) -> some View {
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
    }
  }

  @ViewBuilder
  private func actions(_ stash: Stash) -> some View {
    Group {
      Button("Apply") {
        Task { await model.applyStash(stash, pop: false) }
      }
      Button("Pop") {
        Task { await model.applyStash(stash, pop: true) }
      }
      Button("New Branch…") {
        navigation.present(.stashBranch(stash))
      }
      .help("Apply the stash on a new branch made where it was stashed")
      Button("Drop…", role: .destructive) {
        confirmingDrop = true
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let diffs {
      if diffs.isEmpty {
        ContentUnavailableView("Empty Stash", systemImage: "tray")
      } else {
        FileDiffListView(diffs: diffs, highlightsWordChanges: model.diffHighlightsWordChanges)
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
      let loaded = try await model.stashDiffs(stash)
      // A superseded load (another stash) can finish after this one.
      guard !Task.isCancelled else { return }
      diffs = loaded
      loadErrorMessage = nil
    } catch {
      guard !Task.isCancelled else { return }
      diffs = nil
      loadErrorMessage = error.localizedDescription
    }
    loadedStash = stash
  }
}
