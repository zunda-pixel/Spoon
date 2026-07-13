import SpoonCore
import SwiftUI

@MainActor
struct ResetSheet: View {
  let model: RepositoryModel
  let target: ObjectID
  let targetDescription: String
  @Environment(\.dismiss) private var dismiss
  @State private var mode = ResetMode.mixed
  @State private var isConfirmingHardReset = false

  var body: some View {
    SheetFormLayout(title: "Reset to \(targetDescription)") {
      Picker("Mode", selection: $mode) {
        Text("Soft — keep index and files").tag(ResetMode.soft)
        Text("Mixed — unstage changes").tag(ResetMode.mixed)
        Text("Hard — discard changes").tag(ResetMode.hard)
      }
      .frame(width: 380)

      Text(modeDescription)
        .font(.caption)
        .foregroundStyle(mode == .hard ? .red : .secondary)
        .frame(width: 380, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) {
        dismiss()
      }
      Button("Reset", role: .destructive) {
        if mode == .hard {
          isConfirmingHardReset = true
        } else {
          performReset()
        }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(model.isBusy || model.isSequencing)
    }
    .confirmationDialog(
      "Permanently discard tracked changes?",
      isPresented: $isConfirmingHardReset
    ) {
      Button("Hard Reset to \(target.shortened)", role: .destructive) {
        performReset()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Target: \(targetDescription)\n\nThis moves \(model.currentBranch?.name ?? "HEAD") to the target and permanently discards all tracked index and working-tree changes. Untracked files are not removed."
      )
    }
  }

  private var modeDescription: String {
    switch mode {
    case .soft:
      "Moves the branch while keeping the index and working tree unchanged."
    case .mixed:
      "Moves the branch and resets the index, preserving working-tree files."
    case .hard:
      "Permanently discards tracked index and working-tree changes after the target. A second confirmation is required."
    }
  }

  private func performReset() {
    let mode = mode
    dismiss()
    Task { await model.reset(to: target, mode: mode) }
  }
}
