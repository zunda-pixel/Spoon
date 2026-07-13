public import SwiftUI

import SpoonCore

struct RepositoryModelFocusedKey: FocusedValueKey {
  typealias Value = RepositoryModel
}

extension FocusedValues {
  var repositoryModel: RepositoryModel? {
    get { self[RepositoryModelFocusedKey.self] }
    set { self[RepositoryModelFocusedKey.self] = newValue }
  }
}

/// Repository menu — every toolbar action must also live in a menu with a
/// shortcut. Routed to the active window via focused values.
@MainActor
public struct SpoonCommands: Commands {
  @FocusedValue(\.repositoryModel) private var model

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
      .disabled(unavailable)

      if model?.supportsBackfill == true {
        Button("Backfill Missing Objects") {
          run { await $0.backfill() }
        }
        .disabled(unavailable)
      }

      Button("Push") {
        run { await $0.push(force: false) }
      }
      .keyboardShortcut("u", modifiers: [.shift, .command])
      .disabled(pushUnavailable)

      Button("Force Push with Lease…") {
        model?.requestForcePushConfirmation()
      }
      .keyboardShortcut("u", modifiers: [.option, .shift, .command])
      .disabled(pushUnavailable)

      Divider()

      Button("New Branch…") {
        model?.requestNewBranchSheet()
      }
      .keyboardShortcut("n", modifiers: [.shift, .command])
      .disabled(unavailable)

      Button("Sparse Checkout…") {
        model?.requestSparseCheckoutSheet()
      }
      .disabled(unavailable)

      Button("Stash Changes") {
        run { await $0.saveStash(message: nil, includeUntracked: true) }
      }
      .disabled(unavailable)

      Divider()

      Button("Refresh") {
        run { await $0.refresh() }
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(model == nil)
    }
  }

  private var unavailable: Bool {
    model == nil || model?.isBusy == true
  }

  private var pushUnavailable: Bool {
    unavailable || model?.isSequencing == true
  }

  private func run(_ operation: @escaping @MainActor (RepositoryModel) async -> Void) {
    guard let model else { return }
    Task { await operation(model) }
  }
}
