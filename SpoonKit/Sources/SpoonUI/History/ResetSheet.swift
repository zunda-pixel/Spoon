import SpoonCore
import SwiftUI

@MainActor
struct ResetSheet: View {
  let model: RepositoryModel
  let target: ObjectID
  let targetDescription: String
  @Environment(\.dismiss) private var dismiss
  @State private var mode = ResetMode.mixed

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Reset to \(targetDescription)")
        .font(.headline)
        .lineLimit(1)
      Picker("Mode", selection: $mode) {
        Text("Soft — keep index and files").tag(ResetMode.soft)
        Text("Mixed — unstage changes").tag(ResetMode.mixed)
        Text("Hard — discard changes").tag(ResetMode.hard)
      }
      .frame(width: 380)

      Text(description)
        .font(.caption)
        .foregroundStyle(mode == .hard ? .red : .secondary)
        .frame(width: 380, alignment: .leading)

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Reset", role: .destructive) {
          let mode = mode
          dismiss()
          Task { await model.reset(to: target, mode: mode) }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(model.isBusy || model.isSequencing)
      }
    }
    .padding(20)
  }

  private var description: String {
    switch mode {
    case .soft:
      "Moves the branch while keeping the index and working tree unchanged."
    case .mixed:
      "Moves the branch and resets the index, preserving working-tree files."
    case .hard:
      "Permanently discards tracked index and working-tree changes after the target."
    }
  }
}
