import SpoonCore
import SwiftUI

@MainActor
struct RenameBranchSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var name: String

  init(model: RepositoryModel, branch: Branch) {
    self.model = model
    self.branch = branch
    self._name = State(initialValue: branch.name)
  }

  var body: some View {
    SheetFormLayout(title: "Rename Branch “\(branch.name)”") {
      TextField("Branch name", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(rename)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Rename", action: rename)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValidName)
    }
  }

  private var isValidName: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && !trimmed.contains(" ") && !trimmed.hasPrefix("-")
      && trimmed != branch.name && !model.branches.contains { $0.name == trimmed }
  }

  private func rename() {
    guard isValidName else { return }
    let newName = name.trimmingCharacters(in: .whitespaces)
    dismiss()
    Task { await model.renameBranch(from: branch.name, to: newName) }
  }
}

@MainActor
struct AddWorktreeSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var parentPath: String
  @State private var folderName: String

  init(model: RepositoryModel, branch: Branch) {
    self.model = model
    self.branch = branch
    let root = model.repository.rootURL
    self._parentPath = State(initialValue: root.deletingLastPathComponent().path)
    let safeBranchName = branch.name.replacingOccurrences(of: "/", with: "-")
    self._folderName = State(initialValue: "\(root.lastPathComponent)-\(safeBranchName)")
  }

  var body: some View {
    SheetFormLayout(title: "Add Worktree for “\(branch.name)”") {
      Form {
        DestinationFolderFields(
          parentPath: $parentPath,
          folderName: $folderName,
          onSubmitFolderName: create
        )
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 420)
      Text(destination.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Add Worktree", action: create)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
    }
  }

  private var destination: URL {
    URL(filePath: parentPath, directoryHint: .isDirectory).appending(path: folderName)
  }

  private var isValid: Bool {
    !parentPath.trimmingCharacters(in: .whitespaces).isEmpty
      && !folderName.trimmingCharacters(in: .whitespaces).isEmpty
      && !FileManager.default.fileExists(atPath: destination.path)
  }

  private func create() {
    guard isValid else { return }
    let destination = destination
    dismiss()
    Task { await model.addWorktree(path: destination, branch: branch.name) }
  }
}

@MainActor
struct AddRemoteSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var url = ""

  init(model: RepositoryModel) {
    self.model = model
    self._name = State(initialValue: model.remotes.isEmpty ? "origin" : "")
  }

  var body: some View {
    SheetFormLayout(title: "Add Remote") {
      Form {
        TextField("Name", text: $name, prompt: Text("origin"))
        TextField("URL", text: $url, prompt: Text("https://github.com/owner/repo.git"))
          .onSubmit(add)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 360)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Add", action: add)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
    }
  }

  private var isValid: Bool {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedURL = url.trimmingCharacters(in: .whitespaces)
    return !trimmedName.isEmpty && !trimmedName.contains(" ") && !trimmedURL.isEmpty
      && !model.remotes.contains { $0.name == trimmedName }
  }

  private func add() {
    guard isValid else { return }
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedURL = url.trimmingCharacters(in: .whitespaces)
    dismiss()
    Task { await model.addRemote(name: trimmedName, url: trimmedURL) }
  }
}
