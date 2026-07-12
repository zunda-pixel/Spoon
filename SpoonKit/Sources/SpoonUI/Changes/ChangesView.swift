import SpoonCore
import SwiftUI
import UniformTypeIdentifiers

/// App-private drag payload for moving files between index areas.
/// A dedicated UTType keeps foreign text drags from matching the targets.
private struct ChangePathsPayload: Codable, Transferable {
  var paths: [String]

  static let contentType = UTType(exportedAs: "com.spoon.app.change-paths")

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: contentType)
  }
}

@MainActor
struct ChangesView: View {
  let model: RepositoryModel
  @Binding var selection: Set<RepositoryModel.FileSelection>

  init(model: RepositoryModel, selection: Binding<Set<RepositoryModel.FileSelection>>) {
    self.model = model
    self._selection = selection
  }

  @State private var confirmingDiscard: RepositoryModel.FileSelection?
  /// The first click of a double-click collapses a multi-selection to the
  /// clicked row (List behavior), so remember the just-collapsed selection
  /// long enough for the double-click handler to act on all of it.
  @State private var recentMultiSelection: (rows: Set<RepositoryModel.FileSelection>, at: ContinuousClock.Instant)?

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
    .onChange(of: selection) { previous, _ in
      if previous.count > 1 {
        recentMultiSelection = (previous, .now)
      }
    }
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
    // The section lists are computed filters over all entries; bind them
    // once per render instead of re-filtering on every access.
    let conflicted = status.conflictedEntries
    let staged = status.stagedEntries
    let unstaged = status.unstagedEntries
    let untracked = status.untrackedEntries

    return List(selection: $selection) {
      section("Conflicts", entries: conflicted, area: .conflicted)
      // A visible Changes list always has unstaged content when Staged is
      // empty, so the stage drop target needs no further condition.
      section("Staged", entries: staged, area: .staged, showsEmptyDropTarget: true)
      section(
        "Modified", entries: unstaged, area: .unstaged,
        showsEmptyDropTarget: !staged.isEmpty
      )
      section("Untracked", entries: untracked, area: .untracked)
    }
    // Return mirrors double-click: stage/unstage everything selected.
    .onKeyPress(.return) {
      guard !selection.isEmpty, !model.isBusy else { return .ignored }
      performPrimaryAction(on: selection)
      return .handled
    }
  }

  @ViewBuilder
  private func section(
    _ title: String,
    entries: [FileStatusEntry],
    area: RepositoryModel.ChangeArea,
    showsEmptyDropTarget: Bool = false
  ) -> some View {
    if !entries.isEmpty || showsEmptyDropTarget {
      Section(title) {
        if entries.isEmpty {
          Label(
            area == .staged ? "Drop files here to stage" : "Drop files here to unstage",
            systemImage: "tray.and.arrow.down"
          )
          .foregroundStyle(.tertiary)
          .dropDestination(for: ChangePathsPayload.self) { items, _ in
            handleDrop(items, into: area)
          }
        }
        ForEach(entries) { entry in
          FileStatusRow(entry: entry)
            .tag(RepositoryModel.FileSelection(path: entry.path, area: area))
            // simultaneousGesture keeps single-click selection instant.
            .simultaneousGesture(
              TapGesture(count: 2).onEnded {
                doubleClickAction(for: entry, area: area)
              }
            )
            .contextMenu {
              contextMenu(for: entry, area: area)
            }
            .draggable(dragPayload(for: entry, area: area))
            .dropDestination(for: ChangePathsPayload.self) { items, _ in
              handleDrop(items, into: area)
            }
        }
      }
    }
  }

  // MARK: - Drag & drop between areas

  /// Dragging a selected row carries the whole selection.
  private func dragPayload(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) -> ChangePathsPayload {
    ChangePathsPayload(paths: actionTargets(for: entry, area: area).map(\.path).sorted())
  }

  /// Dropping on Staged stages; dropping anywhere else unstages. Only paths
  /// currently on the other side count, so same-section drops and payloads
  /// gone stale mid-drag are no-ops.
  private func handleDrop(_ items: [ChangePathsPayload], into area: RepositoryModel.ChangeArea) {
    guard let status = model.status else { return }
    let movable: Set<String>
    if area == .staged {
      movable = Set(
        (status.unstagedEntries + status.untrackedEntries + status.conflictedEntries).map(\.path)
      )
    } else {
      movable = Set(status.stagedEntries.map(\.path))
    }
    let paths = items.flatMap(\.paths).filter(movable.contains)
    if area == .staged {
      moveFiles(stage: paths, unstage: [])
    } else {
      moveFiles(stage: [], unstage: paths)
    }
  }

  /// The rows an action applies to: the whole selection when the clicked
  /// row is part of it (Finder convention), else just the clicked row.
  /// Falls back to a multi-selection collapsed moments ago by the
  /// double-click's own first click.
  private func actionTargets(
    for entry: FileStatusEntry,
    area: RepositoryModel.ChangeArea
  ) -> Set<RepositoryModel.FileSelection> {
    let clicked = RepositoryModel.FileSelection(path: entry.path, area: area)
    if selection.count > 1, selection.contains(clicked) {
      return selection
    }
    if let recent = recentMultiSelection,
      recent.rows.contains(clicked),
      ContinuousClock.now - recent.at < .milliseconds(700)
    {
      return recent.rows
    }
    // Not in the current selection (a single-item selection containing the
    // clicked row was already handled above).
    return [clicked]
  }

  /// Double-click moves files across the index: stage from
  /// Modified/Untracked/Conflicts, unstage from Staged. Applies to the
  /// whole selection when the clicked row belongs to it.
  private func doubleClickAction(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) {
    performPrimaryAction(on: actionTargets(for: entry, area: area))
  }

  /// Stage the non-staged targets and unstage the staged ones — shared by
  /// double-click and the Return key.
  private func performPrimaryAction(on targets: Set<RepositoryModel.FileSelection>) {
    moveFiles(
      stage: targets.filter { $0.area != .staged }.map(\.path),
      unstage: targets.filter { $0.area == .staged }.map(\.path)
    )
  }

  /// The single dispatch point behind every stage/unstage entry point
  /// (double-click, Return, context menus, drag & drop): one busy guard,
  /// one Task.
  private func moveFiles(stage stagePaths: [String], unstage unstagePaths: [String]) {
    guard !model.isBusy, !(stagePaths.isEmpty && unstagePaths.isEmpty) else { return }
    Task {
      if !stagePaths.isEmpty {
        await model.stage(paths: stagePaths)
      }
      if !unstagePaths.isEmpty {
        await model.unstage(paths: unstagePaths)
      }
    }
  }

  @ViewBuilder
  private func contextMenu(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) -> some View {
    let targets = actionTargets(for: entry, area: area)
    if targets.count > 1 {
      multiTargetMenu(targets)
    } else {
      singleTargetMenu(for: entry, area: area)
    }
  }

  @ViewBuilder
  private func multiTargetMenu(_ targets: Set<RepositoryModel.FileSelection>) -> some View {
    let stageable = targets.filter { $0.area != .staged }
    let staged = targets.filter { $0.area == .staged }
    if !stageable.isEmpty {
      Button("Stage (\(stageable.count))") {
        moveFiles(stage: stageable.map(\.path), unstage: [])
      }
    }
    if !staged.isEmpty {
      Button("Unstage (\(staged.count))") {
        moveFiles(stage: [], unstage: staged.map(\.path))
      }
    }
  }

  @ViewBuilder
  private func singleTargetMenu(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) -> some View {
    switch area {
    case .staged:
      Button("Unstage") {
        moveFiles(stage: [], unstage: [entry.path])
      }
    case .unstaged:
      Button("Stage") {
        moveFiles(stage: [entry.path], unstage: [])
      }
      Button("Discard Changes…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .untracked:
      Button("Stage") {
        moveFiles(stage: [entry.path], unstage: [])
      }
      Button("Delete File…", role: .destructive) {
        confirmingDiscard = RepositoryModel.FileSelection(path: entry.path, area: area)
      }
    case .conflicted:
      Button("Mark Resolved (Stage)") {
        moveFiles(stage: [entry.path], unstage: [])
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
