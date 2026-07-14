import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct BranchesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Binding var removingWorktree: Worktree?
  @Binding var deletingBranch: Branch?
  let searchText: String
  let openWorktree: (Worktree) -> Void
  @State private var isExpanded = true
  @State private var expandedFolderPaths: Set<String> = []

  var body: some View {
    Section(isExpanded: $isExpanded) {
      if filteredBranches.isEmpty, searchText.hasSidebarSearchQuery {
        Label("No matching branches", systemImage: "magnifyingglass")
          .foregroundStyle(.tertiary)
      }
      ForEach(BranchTreeNode.make(from: filteredBranches)) { node in
        BranchTreeNodeView(
          node: node,
          model: model,
          navigation: navigation,
          isSearching: searchText.hasSidebarSearchQuery,
          expandedFolderPaths: $expandedFolderPaths,
          removingWorktree: $removingWorktree,
          deletingBranch: $deletingBranch,
          openWorktree: openWorktree
        )
      }
    } header: {
      Text("Branches")
    }
    .onChange(of: model.currentBranch?.name, initial: true) {
      guard let currentBranchName = model.currentBranch?.name else { return }
      expandedFolderPaths.formUnion(BranchTreeNode.folderPaths(in: currentBranchName))
    }
    .onChange(of: searchText) {
      if searchText.hasSidebarSearchQuery {
        isExpanded = true
      }
    }
  }

  private var filteredBranches: [Branch] {
    model.branches.filter { branch in
      branch.name.matchesSidebarSearch(searchText)
        || branch.subject.matchesSidebarSearch(searchText)
        || branch.upstream?.matchesSidebarSearch(searchText) == true
    }
  }
}

@MainActor
private struct BranchTreeNodeView: View {
  let node: BranchTreeNode
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let isSearching: Bool
  @Binding var expandedFolderPaths: Set<String>
  @Binding var removingWorktree: Worktree?
  @Binding var deletingBranch: Branch?
  let openWorktree: (Worktree) -> Void

  var body: some View {
    if let branch = node.branch {
      let worktree = model.worktree(for: branch)
      let pullRequest = model.prByBranch[branch.name]
      BranchRowView(
        branch: branch,
        displayName: node.name,
        pullRequest: pullRequest,
        worktree: worktree
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .tag(SidebarItem.branch(branch.name))
      .simultaneousGesture(
        TapGesture().onEnded {
          navigation.sidebarSelection = .branch(branch.name)
        }
      )
      .simultaneousGesture(
        TapGesture(count: 2).onEnded {
          activateBranch(branch, worktree: worktree)
        }
      )
      .contextMenu {
        BranchContextMenu(
          model: model,
          navigation: navigation,
          branch: branch,
          pullRequest: pullRequest,
          worktree: worktree,
          removingWorktree: $removingWorktree,
          deletingBranch: $deletingBranch,
          openWorktree: openWorktree
        )
      }
    } else {
      DisclosureGroup(isExpanded: isFolderExpanded) {
        ForEach(node.children) { child in
          BranchTreeNodeView(
            node: child,
            model: model,
            navigation: navigation,
            isSearching: isSearching,
            expandedFolderPaths: $expandedFolderPaths,
            removingWorktree: $removingWorktree,
            deletingBranch: $deletingBranch,
            openWorktree: openWorktree
          )
        }
      } label: {
        Label(node.name, systemImage: "folder")
      }
    }
  }

  private func activateBranch(_ branch: Branch, worktree: Worktree?) {
    navigation.sidebarSelection = .branch(branch.name)

    if let worktree {
      openWorktree(worktree)
    } else if !branch.isCurrent && !model.isBusy && !model.isSequencing {
      Task { await model.switchBranch(branch.name) }
    }
  }

  private var isFolderExpanded: Binding<Bool> {
    if isSearching {
      return .constant(true)
    }
    return Binding(
      get: { expandedFolderPaths.contains(node.path) },
      set: { isExpanded in
        if isExpanded {
          expandedFolderPaths.insert(node.path)
        } else {
          expandedFolderPaths.remove(node.path)
        }
      }
    )
  }
}

@MainActor
private struct BranchContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let branch: Branch
  let pullRequest: PullRequest?
  let worktree: Worktree?
  @Binding var removingWorktree: Worktree?
  @Binding var deletingBranch: Branch?
  let openWorktree: (Worktree) -> Void

  var body: some View {
    Button("Switch") {
      Task { await model.switchBranch(branch.name) }
    }
    .disabled(branch.isCurrent || model.isBusy || worktree != nil)
    if let pullRequest, let url = URL(string: pullRequest.url) {
      Button("Open Pull Request #\(pullRequest.number)", systemImage: "arrow.up.right.square") {
        NSWorkspace.shared.open(url)
      }
    }
    Divider()
    Button("Merge into \(model.currentBranch?.name ?? "HEAD")…") {
      navigation.present(.mergeBranch(branch))
    }
    .disabled(branch.isCurrent || model.isBusy || model.isSequencing)
    Divider()
    if let worktree {
      Button("Switch to Worktree") { openWorktree(worktree) }
      Button("Open in Finder") {
        NSWorkspace.shared.open(worktree.path)
      }
      if !worktree.isMain {
        Button("Delete Worktree…", role: .destructive) { removingWorktree = worktree }
          .disabled(model.isBusy)
      }
    } else if !branch.isCurrent {
      Button("Create Worktree…") { navigation.present(.addWorktree(branch)) }
        .disabled(model.isBusy)
    }
    Divider()
    Button("New Branch from Here…") {
      navigation.present(.newBranch(startPoint: branch.name))
    }
    .disabled(model.isBusy)
    Button("Rename Branch…") { navigation.present(.renameBranch(branch)) }
      .disabled(model.isBusy)
    Button("Delete Branch…", role: .destructive) { deletingBranch = branch }
      .disabled(branch.isCurrent || model.isBusy || worktree != nil)
  }
}
