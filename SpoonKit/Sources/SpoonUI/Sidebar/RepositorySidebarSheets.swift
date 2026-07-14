import SpoonCore
import SwiftUI

@MainActor
struct RenameBranchSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var renameRemoteBranch = false

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
      if let upstream = branch.upstream {
        Toggle("Also rename remote branch “\(upstream)”", isOn: $renameRemoteBranch)
        Text("This runs multiple Git operations and cannot be completed atomically.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
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
    let upstream = renameRemoteBranch ? branch.upstream : nil
    Task {
      await model.renameBranch(
        from: branch.name,
        to: newName,
        renameRemoteUpstream: upstream
      )
    }
  }
}

@MainActor
struct DeleteBranchSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var deleteRemoteBranch = false
  @State private var forceDelete = false
  /// nil while the merge check runs; the force checkbox only appears once
  /// the branch is known to have commits a plain delete would refuse to drop.
  @State private var requiresForce: Bool?

  var body: some View {
    SheetFormLayout(title: "Delete Branch “\(branch.name)”") {
      Text(explanation)
        .frame(width: 380, alignment: .leading)
      if requiresForce == true {
        Toggle("Force delete, discarding those commits", isOn: $forceDelete)
      }
      if let upstream = branch.upstream {
        Toggle("Also delete remote branch “\(upstream)”", isOn: $deleteRemoteBranch)
        Text("This runs multiple Git operations and cannot be completed atomically.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Delete", role: .destructive) { delete(force: forceDelete) }
        .keyboardShortcut(.defaultAction)
        .disabled(requiresForce == true && !forceDelete)
    }
    .task {
      requiresForce = await model.requiresForceDelete(branch)
    }
  }

  private var explanation: String {
    if requiresForce == true {
      "This branch has commits that are merged into neither HEAD nor its upstream."
    } else {
      "The local branch will be deleted."
    }
  }

  private func delete(force: Bool) {
    let upstream = deleteRemoteBranch ? branch.upstream : nil
    dismiss()
    Task {
      await model.deleteBranch(
        name: branch.name,
        force: force,
        deleteRemoteUpstream: upstream
      )
    }
  }
}

@MainActor
struct DeleteWorktreeSheet: View {
  let model: RepositoryModel
  let worktree: Worktree
  @Environment(\.dismiss) private var dismiss
  @State private var forceRemove = false
  @State private var deleteBranch = false
  @State private var deleteRemoteBranch = false
  @State private var forceDeleteBranch = false
  @State private var branchRequiresForce: Bool?

  var body: some View {
    SheetFormLayout(title: "Delete Worktree “\(worktree.name)”") {
      Text("The worktree folder at \(worktree.path.path) will be deleted.")
        .frame(width: 420, alignment: .leading)
      Toggle("Force delete, discarding local changes", isOn: $forceRemove)

      if let branch {
        Toggle("Also delete branch “\(branch.name)”", isOn: $deleteBranch)
        if deleteBranch, let upstream = branch.upstream {
          Toggle(
            "Also delete remote branch “\(upstream)”",
            isOn: $deleteRemoteBranch
          )
        }
        if deleteBranch, branchRequiresForce == true {
          Text("This branch has commits that are merged into neither HEAD nor its upstream.")
            .frame(width: 420, alignment: .leading)
          Toggle(
            "Force delete, discarding those commits",
            isOn: $forceDeleteBranch
          )
        }
        if deleteBranch {
          Text("This runs multiple Git operations and cannot be completed atomically.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Delete", role: .destructive, action: remove)
        .keyboardShortcut(.defaultAction)
        .disabled(
          deleteBranch
            && (branchRequiresForce == nil
              || (branchRequiresForce == true && !forceDeleteBranch))
        )
    }
    .task {
      guard let branch else { return }
      branchRequiresForce = await model.requiresForceDelete(branch)
    }
  }

  private var branch: Branch? {
    guard let branchName = worktree.branch else { return nil }
    return model.branches.first { $0.name == branchName }
  }

  private func remove() {
    let branchName = deleteBranch ? branch?.name : nil
    let upstream = deleteBranch && deleteRemoteBranch ? branch?.upstream : nil
    let shouldForceRemove = forceRemove
    let shouldForceDeleteBranch = forceDeleteBranch
    dismiss()
    Task {
      await model.removeWorktree(
        path: worktree.path,
        force: shouldForceRemove,
        deleteBranch: branchName,
        forceDeleteBranch: shouldForceDeleteBranch,
        deleteRemoteUpstream: upstream
      )
    }
  }
}

@MainActor
struct AddWorktreeSheet: View {
  let model: RepositoryModel
  let branch: Branch
  let switchToWorktree: (URL) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var parentPath: String
  @State private var folderName: String
  @State private var switchAfterCreation = true

  init(
    model: RepositoryModel,
    branch: Branch,
    switchToWorktree: @escaping (URL) -> Void
  ) {
    self.model = model
    self.branch = branch
    self.switchToWorktree = switchToWorktree
    let root = model.repository.rootURL
    self._parentPath = State(initialValue: root.deletingLastPathComponent().path)
    let safeBranchName = branch.name.replacingOccurrences(of: "/", with: "-")
    self._folderName = State(initialValue: "\(root.lastPathComponent)-\(safeBranchName)")
  }

  var body: some View {
    SheetFormLayout(title: "Create Worktree for “\(branch.name)”") {
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
      Toggle("Switch to new worktree", isOn: $switchAfterCreation)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button(switchAfterCreation ? "Create and Switch" : "Create", action: create)
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
    let shouldSwitch = switchAfterCreation
    dismiss()
    Task {
      guard await model.addWorktree(path: destination, branch: branch.name) else { return }
      if shouldSwitch {
        switchToWorktree(destination)
      }
    }
  }
}
