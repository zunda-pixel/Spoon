import SpoonCore
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

  public init() {}

  public var body: some Commands {
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

      if model?.supportsBackfill == true {
        Button("Backfill Missing Objects") {
          run { await $0.backfill() }
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

      Button("Refresh") {
        run { await $0.refresh() }
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(model == nil)
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
    }
  }

  private func run(_ operation: @escaping @MainActor (RepositoryModel) async -> Void) {
    guard let model else { return }
    Task { await operation(model) }
  }
}
