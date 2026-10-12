import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct BranchesSidebarSection: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Bindable var expansion: SidebarExpansionState
  let searchText: String
  let openWorktree: (Worktree) -> Void

  var body: some View {
    Section(isExpanded: $expansion.branches) {
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
          expandedFolderPaths: $expansion.branchFolderPaths,
          openWorktree: openWorktree
        )
      }
    } header: {
      Text("Branches")
    }
    .onChange(of: model.currentBranch?.name, initial: true) {
      guard let currentBranchName = model.currentBranch?.name else { return }
      expansion.revealBranch(named: currentBranchName)
    }
    .onChange(of: searchText) {
      if searchText.hasSidebarSearchQuery {
        expansion.branches = true
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
  let openWorktree: (Worktree) -> Void

  var body: some View {
    if let branch = node.branch {
      let worktree = model.worktree(for: branch)
      let pullRequest = model.prByBranch[branch.name]
      BranchRowView(
        branch: branch,
        displayName: node.name,
        pullRequest: pullRequest,
        worktree: worktree,
        historyReferenceID: HistoryReferenceFilterID.localBranch(branch.name).id,
        historyModel: model
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .tag(SidebarItem.branch(branch.name))
      .simultaneousGesture(
        TapGesture().onEnded {
          // ⌘/⇧-clicks extend the multi-selection instead of focusing.
          guard !NSEvent.modifierFlags.contains(.command),
            !NSEvent.modifierFlags.contains(.shift)
          else { return }
          navigation.focusHistory(on: branch)
        }
      )
      .simultaneousGesture(
        TapGesture(count: 2).onEnded {
          activateBranch(branch, worktree: worktree)
        }
      )
      .contextMenu {
        let selected = navigation.selectedBranchNames
        if selected.count > 1, selected.contains(branch.name) {
          MultipleBranchesContextMenu(
            model: model,
            navigation: navigation,
            branches: model.branches.filter { selected.contains($0.name) }
          )
        } else {
          BranchContextMenu(
            model: model,
            navigation: navigation,
            branch: branch,
            pullRequest: pullRequest,
            worktree: worktree,
            openWorktree: openWorktree
          )
        }
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
            openWorktree: openWorktree
          )
        }
      } label: {
        Label(node.name, systemImage: "folder")
      }
    }
  }

  private func activateBranch(_ branch: Branch, worktree: Worktree?) {
    navigation.focusHistory(on: branch)

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

/// Actions for several selected local branches.
@MainActor
struct MultipleBranchesContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let branches: [Branch]

  var body: some View {
    Button("Show Only These Branches in History") {
      navigation.select(.history)
      Task {
        await model.focusHistory(onReferences: branches.map { .localBranch($0.name) })
      }
    }
    Divider()
    Button("Delete \(branches.count) Branches…", role: .destructive) {
      navigation.present(.deleteBranches(branches))
    }
    .disabled(model.isBusy)
  }
}

@MainActor
struct BranchContextMenu: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  let branch: Branch
  let pullRequest: PullRequest?
  let worktree: Worktree?
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
    } else if createPullRequestURL(for: branch) != nil {
      Button("Create Pull Request…", systemImage: "arrow.triangle.pull") {
        Task { await createPullRequest() }
      }
      .disabled(model.isBusy)
    }
    Button("Compare Versions…") {
      navigation.present(.compareBranchVersions(branch))
    }
    .help("Compare this branch with its previous position or its upstream, commit by commit")
    Button("Show Only Branches Forked from Here") {
      navigation.select(.history)
      Task { await model.focusHistoryOnBranches(forkedFrom: .localBranch(branch.name)) }
    }
    Divider()
    Button("Merge into \(model.currentBranch?.name ?? "HEAD")…") {
      navigation.present(.mergeBranch(branch))
    }
    .disabled(branch.isCurrent || model.isBusy || model.isSequencing)
    if model.canReplayBranchOntoHead(branch) {
      Button("Rebase onto \(model.currentBranch?.name ?? "HEAD")…") {
        navigation.present(.replayBranch(branch))
      }
      .disabled(model.isBusy || model.isSequencing)
    }
    Button("Reset Current Branch to \(branch.name)…", role: .destructive) {
      navigation.present(ResetBranchTarget(branch: branch).resetSheet)
    }
    .disabled(!ResetBranchTarget.isAvailable(for: branch) || model.isBusy || model.isSequencing)
    Divider()
    if let worktree {
      Button("Switch to Worktree") { openWorktree(worktree) }
      Button("Open in Finder") {
        NSWorkspace.shared.open(worktree.path)
      }
      WorktreeMaintenanceMenuItems(model: model, navigation: navigation, worktree: worktree)
      if !worktree.isMain {
        Button("Delete Worktree…", role: .destructive) {
          navigation.present(.deleteWorktree(worktree))
        }
        .disabled(model.isBusy || worktree.isLocked)
        .help(worktree.isLocked ? "Unlock the worktree to delete it" : "")
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
    Button("Delete Branch…", role: .destructive) {
      navigation.present(.deleteBranch(branch))
    }
      .disabled(branch.isCurrent || model.isBusy || worktree != nil)
  }

  private func createPullRequest() async {
    guard let publishedBranch = await model.publishBranchForPullRequest(branch),
      let url = createPullRequestURL(for: publishedBranch)
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func createPullRequestURL(for branch: Branch) -> URL? {
    PullRequestURLBuilder.createURL(
      for: branch,
      remotes: model.remotes,
      fallbackRepoRef: model.gitHubRepoRef
    )
  }
}
