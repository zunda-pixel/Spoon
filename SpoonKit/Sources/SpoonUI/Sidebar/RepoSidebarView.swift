import SpoonCore
import SwiftUI

@MainActor
struct RepoSidebarView: View {
  let model: RepositoryModel
  @Bindable var navigation: RepositoryNavigationState
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
      SubmodulesSidebarSection(
        model: model,
        navigation: navigation,
        searchText: searchText
      )
      TagsSidebarSection(
        model: model,
        navigation: navigation,
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
