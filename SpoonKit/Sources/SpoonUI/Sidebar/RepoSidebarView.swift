import SpoonCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Binding var selection: SidebarItem?
  @Environment(AppModel.self) private var appModel
  @Environment(\.openWindow) private var openWindow
  @State private var showingAddRemoteSheet = false
  @State private var removingRemote: Remote?
  @State private var addingWorktreeBranch: Branch?
  @State private var removingWorktree: Worktree?
  @State private var deletingBranch: Branch?
  @State private var renamingBranch: Branch?
  @State private var branchingFrom: Branch?
  @State private var deletingTag: Tag?
  @State private var openWorktreeErrorMessage: String?

  init(model: RepositoryModel, selection: Binding<SidebarItem?>) {
    self.model = model
    self._selection = selection
  }

  var body: some View {
    List(selection: $selection) {
      Section("Workspace") {
        Label("Changes", systemImage: "square.and.pencil")
          .badge(model.pendingChangeCount)
          .tag(SidebarItem.changes)
        Label("History", systemImage: "clock")
          .tag(SidebarItem.history)
        if model.gitHubRepoRef != nil {
          Label("Pull Requests", systemImage: "arrow.triangle.pull")
            .badge(model.openPullRequests.count)
            .tag(SidebarItem.pullRequests)
        }
      }

      Section("Branches") {
        ForEach(model.branches) { branch in
          let worktree = model.worktree(for: branch)
          BranchRowView(
            branch: branch,
            pullRequest: model.prByBranch[branch.name],
            worktree: worktree
          )
          .tag(SidebarItem.branch(branch.name))
          .contextMenu {
            Button("Checkout") {
              Task { await model.checkout(branch: branch.name) }
            }
            .disabled(branch.isCurrent || model.isBusy || worktree != nil)
            Divider()
            Button("Merge into \(model.currentBranch?.name ?? "HEAD")") {
              Task { await model.merge(branch: branch.name) }
            }
            .disabled(branch.isCurrent || model.isBusy || model.isSequencing)
            Button("Squash Merge into \(model.currentBranch?.name ?? "HEAD")") {
              Task { await model.merge(branch: branch.name, squash: true) }
            }
            .disabled(branch.isCurrent || model.isBusy || model.isSequencing)
            Divider()
            if let worktree {
              Button("Open Worktree") {
                openWorktree(worktree)
              }
              Button("Remove Worktree…", role: .destructive) {
                removingWorktree = worktree
              }
              .disabled(model.isBusy)
            } else if !branch.isCurrent {
              Button("Add Worktree…") {
                addingWorktreeBranch = branch
              }
              .disabled(model.isBusy)
            }
            Divider()
            Button("New Branch from Here…") {
              branchingFrom = branch
            }
            .disabled(model.isBusy)
            Button("Rename Branch…") {
              renamingBranch = branch
            }
            .disabled(model.isBusy)
            Button("Delete Branch…", role: .destructive) {
              deletingBranch = branch
            }
            .disabled(branch.isCurrent || model.isBusy || worktree != nil)
          }
        }
      }

      if !model.stashes.isEmpty {
        Section("Stashes") {
          ForEach(model.stashes) { stash in
            Label {
              Text(stash.message)
                .lineLimit(1)
                .truncationMode(.tail)
            } icon: {
              Image(systemName: "tray")
            }
            .tag(SidebarItem.stash(stash.index))
            .help(stash.message)
            .contextMenu {
              Button("Apply") {
                Task { await model.applyStash(stash, pop: false) }
              }
              Button("Pop (Apply and Drop)") {
                Task { await model.applyStash(stash, pop: true) }
              }
              Divider()
              Button("Drop…", role: .destructive) {
                Task { await model.dropStash(stash) }
              }
            }
          }
        }
      }

      if !model.tags.isEmpty {
        Section("Tags") {
          ForEach(model.tags) { tag in
            Label {
              HStack {
                Text(tag.name)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(tag.target.shortened)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "tag")
            }
            .help(tag.isAnnotated ? "Annotated tag at \(tag.target.shortened)" : "Tag at \(tag.target.shortened)")
            .contextMenu {
              Button("Delete Tag…", role: .destructive) {
                deletingTag = tag
              }
              .disabled(model.isBusy)
            }
          }
        }
      }

      Section("Remotes") {
        if model.remotes.isEmpty {
          Label("No remotes", systemImage: "network.slash")
            .foregroundStyle(.tertiary)
            .contextMenu {
              addRemoteButton
            }
        }
        ForEach(model.remotes) { remote in
          Label(remote.name, systemImage: "network")
            .tag(SidebarItem.remote(remote.name))
            .help(remote.fetchURL)
            .contextMenu {
              addRemoteButton
              Divider()
              Button("Remove \"\(remote.name)\"…", role: .destructive) {
                removingRemote = remote
              }
            }
        }
      }
    }
    .listStyle(.sidebar)
    .sheet(isPresented: $showingAddRemoteSheet) {
      AddRemoteSheet(model: model)
    }
    .sheet(item: $addingWorktreeBranch) { branch in
      AddWorktreeSheet(model: model, branch: branch)
    }
    .sheet(item: $renamingBranch) { branch in
      RenameBranchSheet(model: model, branch: branch)
    }
    .sheet(item: $branchingFrom) { branch in
      NewBranchSheet(model: model, startPoint: branch.name)
    }
    .confirmationDialog(
      "Remove remote \"\(removingRemote?.name ?? "")\"?",
      isPresented: .init(
        get: { removingRemote != nil },
        set: { if !$0 { removingRemote = nil } }
      )
    ) {
      Button("Remove Remote", role: .destructive) {
        guard let remote = removingRemote else { return }
        Task { await model.removeRemote(name: remote.name) }
      }
    } message: {
      Text("Remote-tracking branches and settings for this remote will be deleted.")
    }
    .confirmationDialog(
      "Remove worktree \"\(removingWorktree?.name ?? "")\"?",
      isPresented: .init(
        get: { removingWorktree != nil },
        set: { if !$0 { removingWorktree = nil } }
      )
    ) {
      Button("Remove Worktree", role: .destructive) {
        guard let worktree = removingWorktree else { return }
        Task { await model.removeWorktree(path: worktree.path, force: false) }
      }
      Button("Force Remove (Discard Changes)", role: .destructive) {
        guard let worktree = removingWorktree else { return }
        Task { await model.removeWorktree(path: worktree.path, force: true) }
      }
    } message: {
      Text(
        "The worktree folder at \(removingWorktree?.path.path ?? "") will be deleted. Remove refuses worktrees with local changes; Force Remove deletes them anyway."
      )
    }
    .confirmationDialog(
      "Delete tag \"\(deletingTag?.name ?? "")\"?",
      isPresented: .init(
        get: { deletingTag != nil },
        set: { if !$0 { deletingTag = nil } }
      )
    ) {
      Button("Delete Tag", role: .destructive) {
        guard let tag = deletingTag else { return }
        Task { await model.deleteTag(name: tag.name) }
      }
    } message: {
      Text("The tag will be removed locally. Remote copies are not affected.")
    }
    .confirmationDialog(
      "Delete branch \"\(deletingBranch?.name ?? "")\"?",
      isPresented: .init(
        get: { deletingBranch != nil },
        set: { if !$0 { deletingBranch = nil } }
      )
    ) {
      Button("Delete", role: .destructive) {
        guard let branch = deletingBranch else { return }
        Task { await model.deleteBranch(name: branch.name, force: false) }
      }
      Button("Force Delete", role: .destructive) {
        guard let branch = deletingBranch else { return }
        Task { await model.deleteBranch(name: branch.name, force: true) }
      }
    } message: {
      Text("Delete refuses branches that are not fully merged; Force Delete removes them anyway.")
    }
    .alert(
      "Could Not Open Worktree",
      isPresented: .init(
        get: { openWorktreeErrorMessage != nil },
        set: { if !$0 { openWorktreeErrorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(openWorktreeErrorMessage ?? "")
    }
  }

  private var addRemoteButton: some View {
    Button("Add Remote…") {
      showingAddRemoteSheet = true
    }
    .disabled(model.isBusy)
  }

  private func openWorktree(_ worktree: Worktree) {
    Task {
      do {
        let repository = try await appModel.openRepository(at: worktree.path)
        openWindow(value: repository.id)
      } catch {
        openWorktreeErrorMessage = error.localizedDescription
      }
    }
  }
}

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
    VStack(alignment: .leading, spacing: 12) {
      Text("Rename Branch \"\(branch.name)\"")
        .font(.headline)
      TextField("Branch name", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(rename)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Rename", action: rename)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValidName)
      }
    }
    .padding(20)
  }

  private var isValidName: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && !trimmed.contains(" ") && !trimmed.hasPrefix("-")
      && trimmed != branch.name
      && !model.branches.contains { $0.name == trimmed }
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
    VStack(alignment: .leading, spacing: 12) {
      Text("Add Worktree for \"\(branch.name)\"")
        .font(.headline)
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
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Add Worktree", action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid)
      }
    }
    .padding(20)
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
    // The conventional first remote name.
    self._name = State(initialValue: model.remotes.isEmpty ? "origin" : "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Add Remote")
        .font(.headline)
      Form {
        TextField("Name", text: $name, prompt: Text("origin"))
        TextField("URL", text: $url, prompt: Text("https://github.com/owner/repo.git"))
          .onSubmit(add)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 360)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Add", action: add)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid)
      }
    }
    .padding(20)
  }

  private var isValid: Bool {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedURL = url.trimmingCharacters(in: .whitespaces)
    return !trimmedName.isEmpty && !trimmedName.contains(" ")
      && !trimmedURL.isEmpty
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

@MainActor
struct BranchRowView: View {
  let branch: Branch
  var pullRequest: PullRequest?
  var worktree: Worktree?

  var body: some View {
    Label {
      HStack(spacing: 4) {
        Text(branch.name)
          .fontWeight(branch.isCurrent ? .semibold : .regular)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        if let pullRequest {
          PRBadgeView(pullRequest: pullRequest)
        }
        if let worktree {
          Image(systemName: "folder")
            .foregroundStyle(.secondary)
            .help("Checked out in worktree: \(worktree.path.path)")
        }
        trackingIndicator
      }
    } icon: {
      Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.trianglehead.branch")
        .foregroundStyle(branch.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
    .help(branch.subject)
  }

  @ViewBuilder
  private var trackingIndicator: some View {
    if branch.upstreamGone {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .help("Upstream branch is gone")
    } else if (branch.ahead ?? 0) > 0 || (branch.behind ?? 0) > 0 {
      HStack(spacing: 2) {
        if let ahead = branch.ahead, ahead > 0 {
          Text("↑\(ahead)")
        }
        if let behind = branch.behind, behind > 0 {
          Text("↓\(behind)")
        }
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }
}
