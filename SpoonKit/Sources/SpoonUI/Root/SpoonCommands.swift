import AppKit
public import SpoonCore
public import SwiftUI

struct RepositoryModelFocusedKey: FocusedValueKey {
  typealias Value = RepositoryModel
}

struct RepositoryNavigationStateFocusedKey: FocusedValueKey {
  typealias Value = RepositoryNavigationState
}

extension FocusedValues {
  var repositoryModel: RepositoryModel? {
    get { self[RepositoryModelFocusedKey.self] }
    set { self[RepositoryModelFocusedKey.self] = newValue }
  }

  var repositoryNavigationState: RepositoryNavigationState? {
    get { self[RepositoryNavigationStateFocusedKey.self] }
    set { self[RepositoryNavigationStateFocusedKey.self] = newValue }
  }
}

/// Repository menu — every toolbar action must also live in a menu with a
/// shortcut. Routed to the active window via focused values.
@MainActor
public struct SpoonCommands: Commands {
  @FocusedValue(\.repositoryModel) private var model
  @FocusedValue(\.repositoryNavigationState) private var navigation
  @Environment(\.openWindow) private var openWindow
  private let appModel: AppModel

  public init(appModel: AppModel) {
    self.appModel = appModel
  }

  public var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        openWindow(id: softwareUpdateWindowID)
        Task { await appModel.updater.checkForUpdates() }
      }
      .disabled(isUpdaterBusy)
    }

    CommandMenu("Repository") {
      Button("Fetch") {
        run { await $0.fetch() }
      }
      .keyboardShortcut("f", modifiers: [.shift, .command])
      .disabled(unavailable)

      Button("Pull") {
        run { await $0.pull() }
      }
      .keyboardShortcut("l", modifiers: [.shift, .command])
      .disabled(repositoryMutationUnavailable)

      if let model {
        Menu("Pull Using") {
          PullMenuItems(model: model)
        }
        .disabled(repositoryMutationUnavailable)
      }

      if model?.isShallow == true {
        Button("Fetch More History…") {
          navigation?.present(.fetchHistory)
        }
        .disabled(repositoryMutationUnavailable)
      }

      if model?.gitCapabilities.supportsBackfill == true {
        Button("Backfill Missing Objects…") {
          navigation?.present(.backfill)
        }
        .disabled(repositoryMutationUnavailable)
      }

      if model?.canDropLargeBlobs == true {
        Button("Remove Large Downloaded Blobs…") {
          navigation?.present(.dropLargeBlobs)
        }
        .disabled(repositoryMutationUnavailable)
      }

      Button("Push") {
        run { await $0.push(force: false) }
      }
      .keyboardShortcut("u", modifiers: [.shift, .command])
      .disabled(pushUnavailable)

      Button("Force Push with Lease…") {
        navigation?.confirm(.forcePush)
      }
      .keyboardShortcut("u", modifiers: [.option, .shift, .command])
      .disabled(pushUnavailable)

      Divider()

      Button("New Branch…") {
        navigation?.present(.newBranch(startPoint: nil))
      }
      .keyboardShortcut("n", modifiers: [.shift, .command])
      .disabled(repositoryMutationUnavailable)

      if model?.gitCapabilities.supportsDeleteMergedBranches == true {
        Button("Delete Merged Branches…") {
          navigation?.present(.deleteMergedBranches)
        }
        .disabled(unavailable)
      }

      Button("Search Code…") {
        navigation?.present(.codeSearch)
      }
      .keyboardShortcut("f", modifiers: [.option, .command])
      .disabled(model == nil || navigation == nil)

      Button("Ignored Files…") {
        navigation?.present(.ignoredFiles)
      }
      .disabled(model == nil || navigation == nil)

      Button("Apply Patches…") {
        chooseAndApplyPatches()
      }
      .disabled(repositoryMutationUnavailable)

      Button("Blame File…") {
        chooseFileToBlame()
      }
      .keyboardShortcut("b", modifiers: [.option, .command])
      .disabled(model == nil || navigation == nil)

      Button("Autosquash Fixup Commits…") {
        navigation?.present(.autosquash)
      }
      .disabled(repositoryMutationUnavailable || model?.currentBranch == nil)

      if let stale = model?.prunableWorktrees, !stale.isEmpty {
        Button("Prune \(stale.count) Missing \(stale.count == 1 ? "Worktree" : "Worktrees")") {
          run { await $0.pruneWorktrees() }
        }
        .disabled(repositoryMutationUnavailable)
      }

      Menu("Submodules") {
        Button("Add Submodule…") {
          navigation?.present(.addSubmodule)
        }
        Button("Update All Submodules") {
          run { await $0.updateSubmodules() }
        }
        .disabled(model?.submodules.isEmpty != false)
        Button("Sync All Submodule URLs") {
          run { await $0.syncSubmodules() }
        }
        .disabled(model?.submodules.isEmpty != false)
      }
      .disabled(repositoryMutationUnavailable)

      Button("Sparse Checkout…") {
        navigation?.present(.sparseCheckout)
      }
      .keyboardShortcut("k", modifiers: [.option, .command])
      .disabled(repositoryMutationUnavailable)

      Button("Stash Changes") {
        run { await $0.saveStash(message: nil, includeUntracked: true) }
      }
      .keyboardShortcut("s", modifiers: [.option, .command])
      .disabled(repositoryMutationUnavailable || model?.status?.isClean != false)

      Button("Stash with Options…") {
        navigation?.present(.stashChanges(paths: []))
      }
      .keyboardShortcut("s", modifiers: [.option, .shift, .command])
      .disabled(repositoryMutationUnavailable || model?.status?.isClean != false)

      if let state = model?.sequencerState {
        Divider()

        Button("Continue \(sequencerName(state.kind))") {
          run { await $0.continueSequencer() }
        }
        .keyboardShortcut(.return, modifiers: [.shift, .command])
        .disabled(unavailable || model?.status?.conflictedEntries.isEmpty == false)

        if state.kind != .merge {
          Button("Skip Current Commit") {
            run { await $0.skipSequencer() }
          }
          .keyboardShortcut(.return, modifiers: [.option, .command])
          .disabled(unavailable)
        }

        Button("Abort \(sequencerName(state.kind))…", role: .destructive) {
          navigation?.confirm(.abortSequencer)
        }
        .disabled(unavailable)
      }

      Divider()

      Button("Maintenance…") {
        navigation?.present(.maintenance)
      }
      .disabled(model == nil || navigation == nil)

      Button("Repository Settings…") {
        navigation?.present(.repositorySettings)
      }
      .keyboardShortcut(",", modifiers: [.option, .command])
      .disabled(model == nil || navigation == nil)

      Button("Refresh") {
        run { await $0.refresh() }
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(model == nil)
    }

    CommandGroup(after: .toolbar) {
      if let model {
        DiffViewMenuItems(model: model)
      }
    }

    CommandGroup(after: .sidebar) {
      Button("Show Changes") {
        navigation?.select(.changes)
      }
      .keyboardShortcut("1", modifiers: .command)
      .disabled(navigation == nil)

      Button("Show History") {
        navigation?.select(.history)
      }
      .keyboardShortcut("2", modifiers: .command)
      .disabled(navigation == nil)

      Button("Show Reflog") {
        navigation?.select(.reflog)
      }
      .keyboardShortcut("3", modifiers: .command)
      .disabled(navigation == nil)

      if model?.gitHubRepoRef != nil {
        Button("Show Pull Requests") {
          navigation?.select(.pullRequests)
        }
        .keyboardShortcut("4", modifiers: .command)
        .disabled(navigation == nil)
      }
    }
  }

  private var isUpdaterBusy: Bool {
    switch appModel.updater.state {
    case .checking, .installing, .readyToRelaunch: true
    default: false
    }
  }

  private var unavailable: Bool {
    model == nil || model?.isBusy == true
  }

  private var pushUnavailable: Bool {
    unavailable || model?.isSequencing == true
  }

  private var repositoryMutationUnavailable: Bool {
    unavailable || model?.isSequencing == true
  }

  private func sequencerName(_ kind: SequencerState.Kind) -> String {
    switch kind {
    case .rebase: "Rebase"
    case .cherryPick: "Cherry-Pick"
    case .revert: "Revert"
    case .merge: "Merge"
    case .applyingPatches: "Patch Application"
    }
  }

  /// Picks patch files (git format-patch output or an mbox) and applies
  /// them as commits onto the current branch.
  private func chooseAndApplyPatches() {
    guard let model else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Apply"
    panel.message = "Choose patch files to apply as commits onto \(model.currentBranch?.name ?? "HEAD")."
    guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
    // Name order is the order git format-patch numbers them in.
    let files = panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    Task { await model.applyPatches(files) }
  }

  /// Picks any file inside the repository and opens its blame.
  private func chooseFileToBlame() {
    guard let model, let navigation else { return }
    let root = model.repository.rootURL.standardizedFileURL.resolvingSymlinksInPath()
    let panel = NSOpenPanel()
    panel.directoryURL = root
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Blame"
    panel.message = "Choose a file in \(model.repository.name) to blame."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let rootPath = root.path(percentEncoded: false)
    let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard filePath.hasPrefix(prefix) else { return }
    navigation.present(.blame(path: String(filePath.dropFirst(prefix.count))))
  }

  private func run(_ operation: @escaping @MainActor (RepositoryModel) async -> Void) {
    guard let model else { return }
    Task { await operation(model) }
  }
}

/// View menu toggles for how diffs are shown.
@MainActor
private struct DiffViewMenuItems: View {
  @Bindable var model: RepositoryModel

  var body: some View {
    Toggle("Ignore Whitespace in Diffs", isOn: $model.diffIgnoresWhitespace)
      .keyboardShortcut("w", modifiers: [.option, .shift, .command])
    Toggle("Highlight Changed Words", isOn: $model.diffHighlightsWordChanges)
  }
}
