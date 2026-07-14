import SpoonCore
import SwiftUI

@MainActor
struct NewBranchSheet: View {
  let model: RepositoryModel
  /// Branch, reflog selector, or any ref the new branch starts at.
  let startPoint: String?
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var switchToBranch = true

  init(model: RepositoryModel, startPoint: String? = nil, suggestedName: String = "") {
    self.model = model
    self.startPoint = startPoint
    self._name = State(initialValue: suggestedName)
  }

  var body: some View {
    SheetFormLayout(
      title: startPoint.map { "New Branch from “\($0)”" } ?? "New Branch"
    ) {
      TextField("Branch name", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(create)
      Toggle("Switch to new branch", isOn: $switchToBranch)
    } actions: {
      Button("Cancel", role: .cancel) {
        dismiss()
      }
      Button(switchToBranch ? "Create and Switch" : "Create", action: create)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValidName)
    }
  }

  private var isValidName: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && !trimmed.contains(" ") && !trimmed.hasPrefix("-")
      && !model.branches.contains { $0.name == trimmed }
  }

  private func create() {
    guard isValidName else { return }
    let branchName = name.trimmingCharacters(in: .whitespaces)
    let shouldSwitch = switchToBranch
    dismiss()
    Task {
      await model.createBranch(
        name: branchName,
        from: startPoint,
        switchToBranch: shouldSwitch
      )
    }
  }
}
