import SpoonCore
import SwiftUI

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
    let hasUnstagedContent =
      !status.unstagedEntries.isEmpty || !status.untrackedEntries.isEmpty
      || !status.conflictedEntries.isEmpty
    let hasStagedContent = !status.stagedEntries.isEmpty

    return List(selection: $selection) {
      section("Conflicts", entries: status.conflictedEntries, area: .conflicted)
      section(
        "Staged", entries: status.stagedEntries, area: .staged,
        emptyDropHint: hasUnstagedContent ? "Drop files here to stage" : nil
      )
      section(
        "Modified", entries: status.unstagedEntries, area: .unstaged,
        emptyDropHint: hasStagedContent ? "Drop files here to unstage" : nil
      )
      section("Untracked", entries: status.untrackedEntries, area: .untracked)
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
    emptyDropHint: String? = nil
  ) -> some View {
    if !entries.isEmpty || emptyDropHint != nil {
      Section(title) {
        if entries.isEmpty, let emptyDropHint {
          Label(emptyDropHint, systemImage: "tray.and.arrow.down")
            .foregroundStyle(.tertiary)
            .dropDestination(for: String.self) { items, _ in
              _ = handleDrop(items, into: area)
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
            .dropDestination(for: String.self) { items, _ in
              _ = handleDrop(items, into: area)
            }
        }
      }
    }
  }

  // MARK: - Drag & drop between areas

  /// Dragging a selected row carries the whole selection.
  private func dragPayload(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) -> String {
    let paths = actionTargets(for: entry, area: area).map(\.path).sorted()
    let encoded = try? JSONEncoder().encode(paths)
    return encoded.map { String(decoding: $0, as: UTF8.self) } ?? entry.path
  }

  /// Dropping decides the action by target section: Staged stages,
  /// everything else unstages. Payloads are validated against paths git
  /// actually reported, so stray text drags are ignored.
  private func handleDrop(_ items: [String], into area: RepositoryModel.ChangeArea) -> Bool {
    guard !model.isBusy, let status = model.status else { return false }
    let knownPaths = Set(status.entries.map(\.path))
    let paths = items
      .flatMap { item -> [String] in
        (try? JSONDecoder().decode([String].self, from: Data(item.utf8))) ?? [item]
      }
      .filter(knownPaths.contains)
    guard !paths.isEmpty else { return false }

    Task {
      if area == .staged {
        await model.stage(paths: paths)
      } else {
        await model.unstage(paths: paths)
      }
    }
    return true
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
    return selection.contains(clicked) ? selection : [clicked]
  }

  /// Double-click moves files across the index: stage from
  /// Modified/Untracked/Conflicts, unstage from Staged. Applies to the
  /// whole selection when the clicked row belongs to it.
  private func doubleClickAction(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) {
    guard !model.isBusy else { return }
    performPrimaryAction(on: actionTargets(for: entry, area: area))
  }

  /// Stage the non-staged targets and unstage the staged ones — shared by
  /// double-click and the Return key.
  private func performPrimaryAction(on targets: Set<RepositoryModel.FileSelection>) {
    let stagePaths = targets.filter { $0.area != .staged }.map(\.path)
    let unstagePaths = targets.filter { $0.area == .staged }.map(\.path)
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
        Task { await model.stage(paths: stageable.map(\.path)) }
      }
    }
    if !staged.isEmpty {
      Button("Unstage (\(staged.count))") {
        Task { await model.unstage(paths: staged.map(\.path)) }
      }
    }
  }

  @ViewBuilder
  private func singleTargetMenu(for entry: FileStatusEntry, area: RepositoryModel.ChangeArea) -> some View {
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
