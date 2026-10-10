import SpoonCore
import SwiftUI

/// Which sidebar sections, remotes, and branch folders are expanded.
/// Worktrees of one repository share its branches, remotes, and tags, so
/// the window keeps this across worktree switches while the rest of the
/// sidebar's state starts over.
@MainActor
@Observable
final class SidebarExpansionState {
  var branches = true
  var branchFolderPaths: Set<String> = []
  var stashes = true
  var remotes = true
  var remoteNames: Set<String> = []
  var remoteFolderPaths: Set<String> = []
  var submodules = true
  var tags = false

  /// Expands the folders holding `branchName`, leaving every other folder
  /// as the user left it.
  func revealBranch(named branchName: String) {
    branchFolderPaths.formUnion(BranchTreeNode.folderPaths(in: branchName))
  }
}

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
  let expansion: SidebarExpansionState
  let openWorktree: (Worktree) -> Void
  @State private var removingRemote: Remote?
  @State private var removingWorktree: Worktree?
  @State private var deletingRemoteBranch: RemoteBranchSelection?
  @State private var searchText = ""

  var body: some View {
    List(selection: $navigation.sidebarSelections) {
      WorkspaceSidebarSection(model: model)
      BranchesSidebarSection(
        model: model,
        navigation: navigation,
        expansion: expansion,
        searchText: searchText,
        openWorktree: openWorktree
      )
      StashesSidebarSection(
        model: model,
        navigation: navigation,
        expansion: expansion,
        searchText: searchText
      )
      RemotesSidebarSection(
        model: model,
        navigation: navigation,
        expansion: expansion,
        removingRemote: $removingRemote,
        removingWorktree: $removingWorktree,
        deletingRemoteBranch: $deletingRemoteBranch,
        searchText: searchText,
        openWorktree: openWorktree
      )
      SubmodulesSidebarSection(
        model: model,
        navigation: navigation,
        expansion: expansion,
        searchText: searchText
      )
      TagsSidebarSection(
        model: model,
        navigation: navigation,
        expansion: expansion,
        searchText: searchText
      )
    }
    .listStyle(.sidebar)
    .onDeleteCommand {
      let branches = model.branches.filter { navigation.selectedBranchNames.contains($0.name) }
      guard !branches.isEmpty, !model.isBusy else { return }
      navigation.present(
        branches.count == 1 ? .deleteBranch(branches[0]) : .deleteBranches(branches)
      )
    }
    .searchable(
      text: $searchText,
      placement: .sidebar,
      prompt: "Search branches, remotes, stashes, and tags"
    )
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
