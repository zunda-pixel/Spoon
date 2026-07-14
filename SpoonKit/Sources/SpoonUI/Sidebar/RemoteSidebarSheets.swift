import SpoonCore
import SwiftUI

@MainActor
struct AddRemoteBranchWorktreeSheet: View {
  let model: RepositoryModel
  let selection: RemoteBranchSelection
  let switchToWorktree: (URL) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var localBranchName: String
  @State private var parentPath: String
  @State private var folderName: String

  init(
    model: RepositoryModel,
    selection: RemoteBranchSelection,
    switchToWorktree: @escaping (URL) -> Void
  ) {
    self.model = model
    self.selection = selection
    self.switchToWorktree = switchToWorktree
    let root = model.repository.rootURL
    self._localBranchName = State(initialValue: selection.localName)
    self._parentPath = State(initialValue: root.deletingLastPathComponent().path)
    let safeName = selection.localName.replacingOccurrences(of: "/", with: "-")
    self._folderName = State(initialValue: "\(root.lastPathComponent)-\(safeName)")
  }

  var body: some View {
    SheetFormLayout(title: "Add Worktree for “\(selection.fullName)”") {
      Form {
        TextField("Local branch", text: $localBranchName)
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
      Button("Add and Switch", action: create)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
    }
  }

  private var destination: URL {
    URL(filePath: parentPath, directoryHint: .isDirectory).appending(path: folderName)
  }

  private var trimmedLocalBranchName: String {
    localBranchName.trimmingCharacters(in: .whitespaces)
  }

  private var isValid: Bool {
    !trimmedLocalBranchName.isEmpty
      && !trimmedLocalBranchName.contains(" ")
      && !trimmedLocalBranchName.hasPrefix("-")
      && !model.branches.contains { $0.name == trimmedLocalBranchName }
      && !parentPath.trimmingCharacters(in: .whitespaces).isEmpty
      && !folderName.trimmingCharacters(in: .whitespaces).isEmpty
      && !FileManager.default.fileExists(atPath: destination.path)
  }

  private func create() {
    guard isValid else { return }
    let destination = destination
    let localBranchName = trimmedLocalBranchName
    dismiss()
    Task {
      guard
        await model.addWorktree(
          path: destination,
          remoteBranch: selection.fullName,
          localBranch: localBranchName
        )
      else { return }
      switchToWorktree(destination)
    }
  }
}

@MainActor
struct RenameRemoteBranchSheet: View {
  let model: RepositoryModel
  let selection: RemoteBranchSelection
  @Environment(\.dismiss) private var dismiss
  @State private var name: String

  init(model: RepositoryModel, selection: RemoteBranchSelection) {
    self.model = model
    self.selection = selection
    self._name = State(initialValue: selection.localName)
  }

  var body: some View {
    SheetFormLayout(title: "Rename Remote Branch “\(selection.fullName)”") {
      TextField("Branch name", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(rename)
      Text(
        "The new branch is pushed before the old branch is deleted. This operation is not atomic."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(width: 360, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Rename", action: rename)
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
    }
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespaces)
  }

  private var isValid: Bool {
    !trimmedName.isEmpty
      && !trimmedName.contains(" ")
      && !trimmedName.hasPrefix("-")
      && trimmedName != selection.localName
      && !(model.remoteBranchesByRemote[selection.remote.name] ?? []).contains {
        $0.name == "\(selection.remote.name)/\(trimmedName)"
      }
  }

  private func rename() {
    guard isValid else { return }
    let newName = trimmedName
    dismiss()
    Task {
      await model.renameRemoteBranch(
        remoteName: selection.remote.name,
        from: selection.localName,
        to: newName
      )
    }
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
