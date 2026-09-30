import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct ChangeFileContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let entry: FileStatusEntry
  let area: RepositoryModel.ChangeArea
  let targets: Set<RepositoryModel.FileSelection>
  @Binding var confirmingDiscard: RepositoryModel.FileSelection?
  @Binding var confirmingMultiDiscard: RepositoryModel.DiscardPlan?
  @Binding var confirmingConflictResolution: ConflictResolutionRequest?
  let moveFiles: (_ stagePaths: [String], _ unstagePaths: [String]) -> Void

  var body: some View {
    if targets.count > 1 {
      multiTargetActions
    } else {
      singleTargetActions
    }
  }

  @ViewBuilder
  private var multiTargetActions: some View {
    let stageable = targets.filter { $0.area != .staged }
    let staged = targets.filter { $0.area == .staged }
    if !stageable.isEmpty {
      Button("Stage (\(stageable.count))") {
        moveFiles(stageable.map(\.path), [])
      }
    }
    if !staged.isEmpty {
      Button("Unstage (\(staged.count))") {
        moveFiles([], staged.map(\.path))
      }
    }
    let plan = RepositoryModel.DiscardPlan(targets)
    if !plan.isEmpty {
      Button(DiscardButtonTitle.make(for: plan), role: .destructive) {
        confirmingMultiDiscard = plan
      }
      .disabled(model.isBusy)
    }
    stashButton(paths: Set(targets.filter { $0.area != .conflicted }.map(\.path)).sorted())
  }

  @ViewBuilder
  private func stashButton(paths: [String]) -> some View {
    if !paths.isEmpty {
      Divider()
      Button(paths.count == 1 ? "Stash File…" : "Stash \(paths.count) Files…") {
        navigation.present(.stashChanges(paths: paths))
      }
      .disabled(model.isBusy || model.isSequencing)
    }
  }

  @ViewBuilder
  private var singleTargetActions: some View {
    switch area {
    case .staged:
      Button("Unstage") { moveFiles([], [entry.path]) }
    case .unstaged:
      Button("Stage") { moveFiles([entry.path], []) }
      Button("Discard Changes…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .untracked:
      Button("Stage") { moveFiles([entry.path], []) }
      Button("Delete File…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .conflicted:
      Button("Mark Resolved (Stage)") { moveFiles([entry.path], []) }
      Divider()
      ForEach([FileStatusEntry.ConflictSide.ours, .theirs], id: \.self) { side in
        Button("Use \(side.displayName(during: model.sequencerState?.kind))…") {
          confirmingConflictResolution = ConflictResolutionRequest(entry: entry, side: side)
        }
        .disabled(model.isBusy)
      }
    }
    if area != .conflicted {
      stashButton(paths: [entry.path])
    }
    if area != .untracked {
      Divider()
      Button("Show File History…") {
        navigation.present(.fileHistory(path: entry.path))
      }
      if FileManager.default.fileExists(atPath: fileURL.path) {
        Button("Blame…") {
          navigation.present(.blame(path: entry.path))
        }
      }
    }
    if FileManager.default.fileExists(atPath: fileURL.path) {
      Divider()
      Button("Open") {
        NSWorkspace.shared.open(fileURL)
      }
      Button("Reveal in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
      }
    }
  }

  private var fileURL: URL {
    model.repository.rootURL.appending(path: entry.path)
  }
}

/// "Discard Changes (3)…", or "Discard (5)…" when untracked files would be
/// deleted too.
enum DiscardButtonTitle {
  static func make(for plan: RepositoryModel.DiscardPlan) -> String {
    plan.untrackedPaths.isEmpty
      ? "Discard Changes (\(plan.count))…"
      : plan.modifiedPaths.isEmpty ? "Delete (\(plan.count))…" : "Discard (\(plan.count))…"
  }
}

extension View {
  /// Confirms, then carries out, discarding a multi-file selection.
  func discardConfirmation(
    _ plan: Binding<RepositoryModel.DiscardPlan?>, model: RepositoryModel
  ) -> some View {
    confirmationDialog(
      plan.wrappedValue?.question ?? "",
      isPresented: .init(
        get: { plan.wrappedValue != nil },
        set: { if !$0 { plan.wrappedValue = nil } }
      ),
      presenting: plan.wrappedValue
    ) { plan in
      Button(plan.modifiedPaths.isEmpty ? "Delete" : "Discard", role: .destructive) {
        Task { await model.discard(plan) }
      }
    } message: { plan in
      Text(
        plan.untrackedPaths.isEmpty
          ? "Unstaged changes are lost. Staged changes are kept. This cannot be undone."
          : "Unstaged changes are lost and untracked files are deleted, not moved to the Trash. Staged changes are kept. This cannot be undone."
      )
    }
  }
}
