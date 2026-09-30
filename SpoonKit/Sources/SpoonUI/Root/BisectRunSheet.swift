import SpoonCore
import SwiftUI

/// Picks the command `git bisect run` tests each commit with.
@MainActor
struct BisectRunSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var command: String

  init(model: RepositoryModel) {
    self.model = model
    self._command = State(initialValue: model.lastBisectRunCommand)
  }

  var body: some View {
    SheetFormLayout(
      title: "Run Bisect Automatically",
      subtitle:
        "Git checks out each commit to test and runs the command in the repository folder. Exit status 0 marks the commit good, 125 skips it, and any other status up to 127 marks it bad."
    ) {
      TextField("Command", text: $command, prompt: Text("swift test --filter ParserTests"))
        .textFieldStyle(.roundedBorder)
        .font(.body.monospaced())
        .onSubmit(run)
      Text("It runs in a login shell, with your usual PATH. Uncommitted changes can get in the way of checking out each commit.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Run", action: run)
        .keyboardShortcut(.defaultAction)
        .disabled(trimmed.isEmpty)
    }
    .frame(width: 520)
  }

  private var trimmed: String { command.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func run() {
    guard !trimmed.isEmpty else { return }
    let command = trimmed
    dismiss()
    Task { await model.runBisect(command: command) }
  }
}
