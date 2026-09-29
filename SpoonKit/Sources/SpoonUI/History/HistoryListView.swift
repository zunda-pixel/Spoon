import SpoonCore
import SwiftUI

@MainActor
struct HistoryListView: View {
  let model: RepositoryModel
  let focus: HistoryFocus?
  @Bindable var navigation: RepositoryNavigationState
  let openWorktree: (Worktree) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var searchText = ""
  @State private var searchField = HistorySearch.Field.message
  @State private var activeSearch: HistorySearch?

  var body: some View {
    VStack(spacing: 0) {
      HistorySearchBar(
        text: $searchText,
        field: $searchField,
        submit: submitSearch,
        clear: clearSearch
      )
      if let activeSearch {
        HistorySearchResultsView(model: model, search: activeSearch, navigation: navigation)
      } else {
        graphHistory
      }
    }
    .onChange(of: searchText) {
      if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
        activeSearch = nil
      }
    }
  }

  private func submitSearch() {
    let text = searchText.trimmingCharacters(in: .whitespaces)
    activeSearch = text.isEmpty ? nil : HistorySearch(text: text, field: searchField)
  }

  private func clearSearch() {
    searchText = ""
    activeSearch = nil
  }

  private var graphHistory: some View {
    ScrollViewReader { proxy in
      Group {
        if model.historyRows.isEmpty {
          if model.isLoadingHistory {
            ProgressView()
          } else {
            ContentUnavailableView(
              "No Commits",
              systemImage: "clock",
              description: Text("This repository has no commits yet.")
            )
          }
        } else {
          List(selection: $navigation.selectedCommitID) {
            ForEach(model.historyRows) { row in
              CommitGraphRowView(
                model: model,
                navigation: navigation,
                row: row,
                referenceLabels: referenceLabelsByOID[row.commit.oid] ?? [],
                selectedReference: focus?.reference,
                openWorktree: openWorktree
              )
              .tag(row.id)
              .id(row.id)
              .listRowSeparator(.hidden)
              .contextMenu {
                commitMenu(row.commit)
              }
              .onAppear {
                if row.id == model.historyRows.last?.id, model.hasMoreHistory {
                  Task { await model.loadMoreHistory() }
                }
              }
            }
            if model.hasMoreHistory {
              HStack {
                Spacer()
                ProgressView()
                  .controlSize(.small)
                Spacer()
              }
              .listRowSeparator(.hidden)
            }
          }
          .listStyle(.plain)
        }
      }
      .task(id: focus) {
        await loadHistoryAndFocus(using: proxy)
      }
    }
  }

  private var referenceLabelsByOID: [ObjectID: [HistoryReferenceLabel]] {
    HistoryReferenceLabelBuilder.build(
      branches: model.branches,
      remoteBranchesByRemote: model.remoteBranchesByRemote,
      worktrees: model.worktrees,
      tags: model.tags,
      stashes: model.stashes,
      activeWorktreeRoot: model.repository.rootURL,
      selectedReference: focus?.reference,
      visibleReferenceIDs: model.visibleHistoryReferenceIDs
    )
  }

  private func loadHistoryAndFocus(using proxy: ScrollViewProxy) async {
    guard await waitForCurrentHistoryLoad() else { return }
    await model.loadHistoryIfNeeded()
    guard await waitForCurrentHistoryLoad(), let focus else { return }

    if !model.historyRows.contains(where: { $0.commit.oid == focus.tip }) {
      guard await model.ensureCommitLoaded(focus.tip) else { return }
    }

    guard
      !Task.isCancelled,
      model.historyRows.contains(where: { $0.commit.oid == focus.tip })
    else {
      return
    }

    navigation.selectedCommitID = focus.tip.rawValue
    await Task.yield()
    guard !Task.isCancelled else { return }
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
      proxy.scrollTo(focus.tip.rawValue, anchor: .center)
    }
  }

  private func waitForCurrentHistoryLoad() async -> Bool {
    while model.isLoadingHistory {
      do {
        try await Task.sleep(for: .milliseconds(20))
      } catch {
        return false
      }
    }
    return !Task.isCancelled
  }

  @ViewBuilder
  private func commitMenu(_ commit: Commit) -> some View {
    let branches = localBranches(on: commit)
    let tags = tags(on: commit)
    ForEach(branches) { branch in
      Menu(branchMenuTitle(for: branch)) {
        Button("Select Branch") {
          navigation.focusHistory(on: branch)
        }
        Divider()
        BranchContextMenu(
          model: model,
          navigation: navigation,
          branch: branch,
          pullRequest: model.prByBranch[branch.name],
          worktree: model.worktree(for: branch),
          openWorktree: openWorktree
        )
      }
    }
    ForEach(tags) { tag in
      Menu("Tag “\(tag.name)”") {
        Button("Select Tag") {
          navigation.focusHistory(on: tag)
        }
        Divider()
        TagContextMenu(
          model: model,
          tag: tag,
          navigation: navigation
        )
      }
    }
    if !branches.isEmpty || !tags.isEmpty {
      Divider()
    }
    RevisionContextMenu(
      model: model,
      navigation: navigation,
      oid: commit.oid,
      startPoint: commit.oid.rawValue,
      targetDescription: "\(commit.oid.shortened) — \(commit.subject)"
    )
    Divider()
    Button("Tag Commit…") {
      navigation.present(.tag(commit))
    }
    .disabled(model.isBusy)
    let movableBranches = model.branchesMovable(to: commit.oid)
    if !movableBranches.isEmpty {
      Menu("Move Branch Here") {
        ForEach(movableBranches) { branch in
          Button("\(branch.name)…") {
            navigation.present(.moveBranch(branch, to: commit))
          }
        }
      }
      .disabled(model.isBusy)
    }
    Divider()
    Button("Interactive Rebase from Here…") {
      navigation.present(.rebase(commit))
    }
    .disabled(commit.isMerge || model.isBusy || model.isSequencing)
    if model.canRewordCommit(commit) {
      Button("Edit Commit Message…") {
        navigation.present(.rewordCommit(commit))
      }
      .disabled(model.isBusy || model.isSequencing)
    }
    if model.canFixupCommit(commit) {
      Button("Fixup Staged Changes into This Commit…") {
        navigation.present(.fixupCommit(commit))
      }
      .disabled(model.isBusy || model.isSequencing)
    }
    if model.canDropCommit(commit) {
      Button("Drop Commit…", role: .destructive) {
        navigation.present(.dropCommit(commit))
      }
      .disabled(model.isBusy || model.isSequencing)
    }
    Divider()
    if model.isBisecting, model.bisectResult == nil {
      Button("Mark as Good for Bisect") {
        Task { await model.markBisect(.good, revision: commit.oid) }
      }
      .disabled(model.isBusy)
      Button("Mark as Bad for Bisect") {
        Task { await model.markBisect(.bad, revision: commit.oid) }
      }
      .disabled(model.isBusy)
    } else if model.canStartBisect(from: commit) {
      Button("Bisect from Here…") {
        navigation.present(.startBisect(commit))
      }
      .disabled(model.isBusy)
      .help("Find which later commit introduced a problem, treating this commit as good")
    }
    Divider()
    Button("Cherry-Pick onto \(model.currentBranch?.name ?? "HEAD")") {
      Task { await model.cherryPick(commit.oid) }
    }
    .disabled(model.isBusy || model.isSequencing)
    if !commit.isMerge, model.canRevert(commit.oid) {
      Button("Revert Commit") {
        Task { await model.revert(commit.oid) }
      }
      .disabled(model.isBusy || model.isSequencing)
    }
  }

  private func localBranches(on commit: Commit) -> [Branch] {
    (referenceLabelsByOID[commit.oid] ?? []).compactMap { label in
      guard case .localBranch(let name) = label.referenceIdentity else { return nil }
      return model.branches.first { $0.name == name }
    }
  }

  private func branchMenuTitle(for branch: Branch) -> String {
    if model.worktree(for: branch) != nil {
      return "Worktree Branch “\(branch.name)”"
    }
    return "Branch “\(branch.name)”"
  }

  private func tags(on commit: Commit) -> [Tag] {
    (referenceLabelsByOID[commit.oid] ?? []).compactMap { label in
      guard case .tag(let name) = label.referenceIdentity else { return nil }
      return model.tags.first { $0.name == name }
    }
  }
}

@MainActor
struct TagCommitSheet: View {
  let model: RepositoryModel
  let commit: Commit
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var message = ""
  @State private var pushToRemotes = false

  init(model: RepositoryModel, commit: Commit) {
    self.model = model
    self.commit = commit
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tag \(commit.oid.shortened) — \(commit.subject)")
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
      Form {
        TextField("Tag name", text: $name, prompt: Text("v1.0.0"))
          .onSubmit(create)
        TextField("Message (optional; makes the tag annotated)", text: $message)
        Toggle("Push to all remotes", isOn: $pushToRemotes)
          .disabled(model.remotes.isEmpty)
      }
      .textFieldStyle(.roundedBorder)
      .frame(width: 380)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Create Tag", action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid)
      }
    }
    .padding(20)
  }

  private var isValid: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && !trimmed.contains(" ")
      && !model.tags.contains { $0.name == trimmed }
  }

  private func create() {
    guard isValid else { return }
    let tagName = name.trimmingCharacters(in: .whitespaces)
    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    dismiss()
    Task {
      await model.createTag(
        name: tagName,
        at: commit.oid,
        message: trimmedMessage.isEmpty ? nil : trimmedMessage,
        pushToRemotes: pushToRemotes
      )
    }
  }
}
