import SpoonCore
import SwiftUI

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  @Environment(AppModel.self) private var appModel
  @Environment(\.openWindow) private var openWindow
  @State private var removingRemote: Remote?
  @State private var removingWorktree: Worktree?
  @State private var deletingBranch: Branch?
  @State private var deletingTag: Tag?
  @State private var deletingRemoteTag: RemoteTagSelection?
  @State private var openWorktreeErrorMessage: String?

  var body: some View {
    List(selection: $navigation.sidebarSelection) {
      WorkspaceSidebarSection(model: model)
      BranchesSidebarSection(
        model: model,
        navigation: navigation,
        removingWorktree: $removingWorktree,
        deletingBranch: $deletingBranch,
        openWorktree: openWorktree
      )
      StashesSidebarSection(model: model)
      TagsSidebarSection(
        model: model,
        deletingTag: $deletingTag,
        deletingRemoteTag: $deletingRemoteTag
      )
      RemotesSidebarSection(
        model: model,
        navigation: navigation,
        removingRemote: $removingRemote
      )
    }
    .listStyle(.sidebar)
    .confirmationDialog(
      "Remove remote “\(removingRemote?.name ?? "")”?",
      isPresented: binding(for: $removingRemote)
    ) {
      Button("Remove Remote", role: .destructive) {
        guard let remote = removingRemote else { return }
        Task { await model.removeRemote(name: remote.name) }
      }
    } message: {
      Text("Remote-tracking branches and settings for this remote will be deleted.")
    }
    .confirmationDialog(
      "Remove worktree “\(removingWorktree?.name ?? "")”?",
      isPresented: binding(for: $removingWorktree)
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
      "Delete tag “\(deletingTag?.name ?? "")”?",
      isPresented: binding(for: $deletingTag)
    ) {
      Button("Delete Tag", role: .destructive) {
        guard let tag = deletingTag else { return }
        Task { await model.deleteTag(name: tag.name) }
      }
    } message: {
      Text("The tag will be removed locally. Remote copies are not affected.")
    }
    .confirmationDialog(
      "Delete tag “\(deletingRemoteTag?.tag.name ?? "")” from \(deletingRemoteTag?.remote.name ?? "remote")?",
      isPresented: binding(for: $deletingRemoteTag)
    ) {
      Button("Delete from Remote", role: .destructive) {
        guard let selection = deletingRemoteTag else { return }
        Task {
          await model.deleteRemoteTag(name: selection.tag.name, from: selection.remote.name)
        }
      }
    } message: {
      Text("The local tag will be kept.")
    }
    .confirmationDialog(
      "Delete branch “\(deletingBranch?.name ?? "")”?",
      isPresented: binding(for: $deletingBranch)
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

  private func binding<Value>(for value: Binding<Value?>) -> Binding<Bool> {
    Binding(
      get: { value.wrappedValue != nil },
      set: { if !$0 { value.wrappedValue = nil } }
    )
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
