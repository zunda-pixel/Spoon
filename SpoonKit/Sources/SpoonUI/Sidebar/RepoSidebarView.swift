import SpoonCore
import SwiftUI

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  let openWorktree: (Worktree) -> Void
  @State private var removingRemote: Remote?
  @State private var removingWorktree: Worktree?
  @State private var deletingBranch: Branch?
  @State private var deletingRemoteBranch: RemoteBranchSelection?
  @State private var deletingTag: Tag?
  @State private var deletingRemoteTag: RemoteTagSelection?
  @State private var searchText = ""

  var body: some View {
    List(selection: $navigation.sidebarSelection) {
      WorkspaceSidebarSection(model: model)
      BranchesSidebarSection(
        model: model,
        navigation: navigation,
        removingWorktree: $removingWorktree,
        deletingBranch: $deletingBranch,
        searchText: searchText,
        openWorktree: openWorktree
      )
      StashesSidebarSection(model: model, searchText: searchText)
      RemotesSidebarSection(
        model: model,
        navigation: navigation,
        removingRemote: $removingRemote,
        removingWorktree: $removingWorktree,
        deletingRemoteBranch: $deletingRemoteBranch,
        searchText: searchText,
        openWorktree: openWorktree
      )
      TagsSidebarSection(
        model: model,
        deletingTag: $deletingTag,
        deletingRemoteTag: $deletingRemoteTag,
        searchText: searchText
      )
    }
    .listStyle(.sidebar)
    .searchable(
      text: $searchText,
      placement: .sidebar,
      prompt: "Search branches, remotes, stashes, and tags"
    )
    .sheet(item: $deletingBranch) { branch in
      DeleteBranchSheet(model: model, branch: branch)
    }
    .sheet(item: $removingWorktree) { worktree in
      DeleteWorktreeSheet(model: model, worktree: worktree)
    }
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
      "Delete remote branch “\(deletingRemoteBranch?.fullName ?? "")”?",
      isPresented: binding(for: $deletingRemoteBranch)
    ) {
      Button("Delete from Remote", role: .destructive) {
        guard let selection = deletingRemoteBranch else { return }
        Task {
          await model.deleteRemoteBranch(
            name: selection.localName,
            from: selection.remote.name
          )
        }
      }
    } message: {
      Text(
        "The remote branch will be permanently deleted. A matching local branch is not affected.")
    }
  }

  private func binding<Value>(for value: Binding<Value?>) -> Binding<Bool> {
    Binding(
      get: { value.wrappedValue != nil },
      set: { if !$0 { value.wrappedValue = nil } }
    )
  }
}
