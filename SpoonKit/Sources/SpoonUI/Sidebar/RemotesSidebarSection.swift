import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct RemotesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Binding var removingRemote: Remote?
  @Binding var removingWorktree: Worktree?
  @Binding var deletingRemoteBranch: RemoteBranchSelection?
  let searchText: String
  let openWorktree: (Worktree) -> Void
  @State private var isExpanded = true
  @State private var expandedRemoteNames: Set<String> = []
  @State private var expandedFolderPaths: Set<String> = []

  var body: some View {
    Section(isExpanded: $isExpanded) {
      if filteredRemotes.isEmpty {
        Label(
          searchText.hasSidebarSearchQuery ? "No matching remotes or branches" : "No remotes",
          systemImage: searchText.hasSidebarSearchQuery ? "magnifyingglass" : "network.slash"
        )
        .foregroundStyle(.tertiary)
        .contextMenu { addRemoteButton }
      }
      ForEach(filteredRemotes) { remote in
        DisclosureGroup(isExpanded: isRemoteExpanded(remote)) {
          ForEach(
            BranchTreeNode.make(
              from: filteredBranches(for: remote),
              removingPrefix: "\(remote.name)/"
            )
          ) { node in
            RemoteBranchTreeNodeView(
              node: node,
              remote: remote,
              model: model,
              navigation: navigation,
              isSearching: searchText.hasSidebarSearchQuery,
              expandedFolderPaths: $expandedFolderPaths,
              removingWorktree: $removingWorktree,
              deletingRemoteBranch: $deletingRemoteBranch,
              openWorktree: openWorktree
            )
          }
        } label: {
          Label(remote.name, systemImage: "network")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(SidebarItem.remote(remote.name))
            .help(remote.fetchURL)
            .simultaneousGesture(
              TapGesture().onEnded {
                navigation.sidebarSelection = .remote(remote.name)
              }
            )
            .contextMenu {
              addRemoteButton
              Divider()
              Button("Push All Tags") { Task { await model.pushAllTags(to: remote.name) } }
                .disabled(model.tags.isEmpty || model.isBusy)
              Divider()
              Button("Remove “\(remote.name)”…", role: .destructive) {
                removingRemote = remote
              }
            }
        }
      }
    } header: {
      Text("Remotes")
    }
    .onChange(of: searchText) {
      if searchText.hasSidebarSearchQuery {
        isExpanded = true
      }
    }
  }

  private var addRemoteButton: some View {
    Button("Add Remote…") { navigation.present(.addRemote) }
      .disabled(model.isBusy)
  }

  private var filteredRemotes: [Remote] {
    model.remotes.filter { remote in
      remoteMatchesSearch(remote)
        || (model.remoteBranchesByRemote[remote.name] ?? []).contains(
          where: branchMatchesSearch
        )
    }
  }

  private func filteredBranches(for remote: Remote) -> [Branch] {
    let branches = model.remoteBranchesByRemote[remote.name] ?? []
    guard searchText.hasSidebarSearchQuery else { return branches }
    if remoteMatchesSearch(remote) {
      return branches
    }
    return branches.filter(branchMatchesSearch)
  }

  private func remoteMatchesSearch(_ remote: Remote) -> Bool {
    remote.name.matchesSidebarSearch(searchText)
      || remote.fetchURL.matchesSidebarSearch(searchText)
      || remote.pushURL?.matchesSidebarSearch(searchText) == true
  }

  private func branchMatchesSearch(_ branch: Branch) -> Bool {
    branch.name.matchesSidebarSearch(searchText)
      || branch.subject.matchesSidebarSearch(searchText)
  }

  private func isRemoteExpanded(_ remote: Remote) -> Binding<Bool> {
    if searchText.hasSidebarSearchQuery {
      return .constant(true)
    }
    return Binding(
      get: { expandedRemoteNames.contains(remote.name) },
      set: { expanded in
        if expanded {
          expandedRemoteNames.insert(remote.name)
        } else {
          expandedRemoteNames.remove(remote.name)
        }
      }
    )
  }
}

@MainActor
private struct RemoteBranchTreeNodeView: View {
  let node: BranchTreeNode
  let remote: Remote
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let isSearching: Bool
  @Binding var expandedFolderPaths: Set<String>
  @Binding var removingWorktree: Worktree?
  @Binding var deletingRemoteBranch: RemoteBranchSelection?
  let openWorktree: (Worktree) -> Void

  var body: some View {
    if let branch = node.branch {
      let selection = RemoteBranchSelection(remote: remote, branch: branch)
      let localBranch = model.branches.first { $0.name == selection.localName }
      let worktree = localBranch.flatMap { model.worktree(for: $0) }
      BranchRowView(
        branch: branch,
        displayName: node.name,
        pullRequest: nil,
        worktree: worktree,
        showsTrackingStatus: false
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .tag(SidebarItem.remoteBranch(remote: remote.name, branch: branch.name))
      .simultaneousGesture(
        TapGesture().onEnded {
          navigation.focusHistory(on: branch, remoteName: remote.name)
        }
      )
      .simultaneousGesture(
        TapGesture(count: 2).onEnded {
          activate(selection, localBranch: localBranch, worktree: worktree)
        }
      )
      .contextMenu {
        remoteBranchContextMenu(
          selection,
          localBranch: localBranch,
          worktree: worktree
        )
      }
    } else {
      DisclosureGroup(isExpanded: isFolderExpanded) {
        ForEach(node.children) { child in
          RemoteBranchTreeNodeView(
            node: child,
            remote: remote,
            model: model,
            navigation: navigation,
            isSearching: isSearching,
            expandedFolderPaths: $expandedFolderPaths,
            removingWorktree: $removingWorktree,
            deletingRemoteBranch: $deletingRemoteBranch,
            openWorktree: openWorktree
          )
        }
      } label: {
        Label(node.name, systemImage: "folder")
      }
    }
  }

  @ViewBuilder
  private func remoteBranchContextMenu(
    _ selection: RemoteBranchSelection,
    localBranch: Branch?,
    worktree: Worktree?
  ) -> some View {
    Button(worktree == nil ? "Switch" : "Switch to Worktree") {
      activate(selection, localBranch: localBranch, worktree: worktree)
    }
    .disabled(
      model.isBusy || model.isSequencing
        || (localBranch?.isCurrent == true && worktree == nil)
    )
    Divider()
    Button("Merge into \(model.currentBranch?.name ?? "HEAD")…") {
      navigation.present(.mergeBranch(selection.branch))
    }
    .disabled(model.isBusy || model.isSequencing)
    Divider()
    if let worktree {
      Button("Open in Finder") {
        NSWorkspace.shared.open(worktree.path)
      }
      if !worktree.isMain {
        Button("Delete Worktree…", role: .destructive) {
          removingWorktree = worktree
        }
        .disabled(model.isBusy)
      }
    } else if let localBranch {
      Button("Create Worktree…") {
        navigation.present(.addWorktree(localBranch))
      }
      .disabled(localBranch.isCurrent || model.isBusy)
    } else {
      Button("Create Worktree…") {
        navigation.present(.addRemoteWorktree(selection))
      }
      .disabled(model.isBusy)
    }
    Divider()
    Button("New Branch from Here…") {
      navigation.present(.newBranch(startPoint: selection.fullName))
    }
    .disabled(model.isBusy)
    Button("Rename Remote Branch…") {
      navigation.present(.renameRemoteBranch(selection))
    }
    .disabled(model.isBusy)
    Button("Delete Remote Branch…", role: .destructive) {
      deletingRemoteBranch = selection
    }
    .disabled(model.isBusy)
  }

  private func activate(
    _ selection: RemoteBranchSelection,
    localBranch: Branch?,
    worktree: Worktree?
  ) {
    navigation.focusHistory(on: selection.branch, remoteName: remote.name)
    guard !model.isBusy, !model.isSequencing else { return }

    if let worktree {
      openWorktree(worktree)
    } else if let localBranch {
      if !localBranch.isCurrent {
        Task { await model.switchBranch(localBranch.name) }
      }
    } else {
      Task { await model.switchToRemoteBranch(selection.fullName) }
    }
  }

  private var isFolderExpanded: Binding<Bool> {
    if isSearching {
      return .constant(true)
    }
    let folderID = "\(remote.name)/\(node.path)"
    return Binding(
      get: { expandedFolderPaths.contains(folderID) },
      set: { expanded in
        if expanded {
          expandedFolderPaths.insert(folderID)
        } else {
          expandedFolderPaths.remove(folderID)
        }
      }
    )
  }
}
