import SpoonCore
import SwiftUI

/// Names the branch `git stash branch` creates for a stash.
@MainActor
struct StashBranchSheet: View {
  let model: RepositoryModel
  let stash: Stash
  @Environment(\.dismiss) private var dismiss
  @State private var name: String

  init(model: RepositoryModel, stash: Stash) {
    self.model = model
    self.stash = stash
    self._name = State(initialValue: Self.suggestedName(for: stash.message))
  }

  /// "On main: Try a longer greeting" → "try-a-longer-greeting". git's own
  /// "WIP on main: 4ae2b1b subject" names suggest nothing, since the
  /// subject is the commit's, not the stash's.
  static func suggestedName(for message: String) -> String {
    guard message.hasPrefix("On "), let colon = message.firstIndex(of: ":") else { return "" }
    let words = message[message.index(after: colon)...].lowercased()
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    return words.prefix(6).joined(separator: "-")
  }

  var body: some View {
    SheetFormLayout(
      title: "New Branch from \(stash.reference)",
      subtitle:
        "The branch starts at the commit the changes were stashed on, where they apply without conflicts. Spoon switches to it, applies the stash, and drops it once applied."
    ) {
      Text(stash.message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      TextField("Branch name", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)
        .onSubmit(create)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Create and Switch", action: create)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValidName)
    }
    .frame(width: 440)
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

  private var isValidName: Bool {
    !trimmedName.isEmpty && !trimmedName.contains(" ") && !trimmedName.hasPrefix("-")
      && !model.branches.contains { $0.name == trimmedName }
  }

  private func create() {
    guard isValidName else { return }
    let name = trimmedName
    dismiss()
    Task { await model.branchFromStash(stash, name: name) }
  }
}
