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
  /// A revert that includes a merge, awaiting confirmation.
  @State private var revertingWithMerge: PendingRevert?

  private struct PendingRevert {
    var commits: [Commit]
    var commit: Bool
  }

  var body: some View {
    VStack(spacing: 0) {
      HistorySearchBar(
        text: $searchText,
        field: $searchField,
        submit: submitSearch,
        clear: clearSearch
      )
      if model.isShallow {
        ShallowHistoryBanner(model: model, navigation: navigation)
      }
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
    .confirmationDialog(
      revertingWithMerge?.commits.count == 1
        ? "Revert this merge?" : "Revert these commits, including a merge?",
      isPresented: .init(
        get: { revertingWithMerge != nil },
        set: { if !$0 { revertingWithMerge = nil } }
      )
    ) {
      Button(revertingWithMerge?.commit == false ? "Revert Without Committing" : "Revert") {
        guard let pending = revertingWithMerge else { return }
        Task { await model.revert(pending.commits, commit: pending.commit) }
      }
    } message: {
      Text(
        "The changes the merge brought into its first parent are undone. Once the revert is committed, git treats that branch as already merged: merging it again won’t bring those changes back until the revert is itself reverted."
      )
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
          List(selection: $navigation.selectedCommitIDs) {
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
                let selected = selectedCommits
                if selected.count > 1, selected.contains(where: { $0.oid == row.commit.oid }) {
                  multipleCommitsMenu(selected)
                } else {
                  commitMenu(row.commit)
                }
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

  /// The selected commits in history order (newest first).
  private var selectedCommits: [Commit] {
    let ids = navigation.selectedCommitIDs
    guard ids.count > 1 else { return [] }
    return model.historyRows.map(\.commit).filter { ids.contains($0.id) }
  }

  @ViewBuilder
  private func multipleCommitsMenu(_ commits: [Commit]) -> some View {
    let containsMerge = commits.contains(where: \.isMerge)
    Button("Cherry-Pick \(commits.count) Commits onto \(model.currentBranch?.name ?? "HEAD")") {
      Task { await model.cherryPick(commits) }
    }
    .disabled(model.isBusy || model.isSequencing)
    .help(containsMerge ? mergeHelp : "")
    cherryPickOptionsMenu(commits)
    let canRevert = commits.allSatisfy { model.canRevert($0.oid) }
    Button("Revert \(commits.count) Commits\(containsMerge ? "…" : "")") {
      revert(commits, commit: true)
    }
    .disabled(model.isBusy || model.isSequencing || !canRevert)
    Button("Revert \(commits.count) Commits Without Committing\(containsMerge ? "…" : "")") {
      revert(commits, commit: false)
    }
    .disabled(model.isBusy || model.isSequencing || !canRevert)
    .help(revertWithoutCommittingHelp)
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
    if model.canCommitFixup(for: commit) {
      Button("Commit Staged Changes as Fixup") {
        Task { await model.commitFixup(for: commit) }
      }
      .disabled(model.isBusy)
      .help("Record the staged changes as “fixup! \(commit.subject)” to fold in with Autosquash")
    }
    if commit.subject.hasPrefix("fixup! ") || commit.subject.hasPrefix("squash! ")
      || commit.subject.hasPrefix("amend! ")
    {
      Button("Autosquash Fixup Commits…") {
        navigation.present(.autosquash)
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
    Button(
      "Cherry-Pick \(commit.isMerge ? "Merge " : "")onto \(model.currentBranch?.name ?? "HEAD")"
    ) {
      Task { await model.cherryPick([commit]) }
    }
    .disabled(model.isBusy || model.isSequencing)
    .help(commit.isMerge ? mergeHelp : "")
    cherryPickOptionsMenu([commit])
    if model.canRevert(commit.oid) {
      Button(commit.isMerge ? "Revert Merge…" : "Revert Commit") {
        revert([commit], commit: true)
      }
      .disabled(model.isBusy || model.isSequencing)
      Button(
        commit.isMerge ? "Revert Merge Without Committing…" : "Revert Without Committing"
      ) {
        revert([commit], commit: false)
      }
      .disabled(model.isBusy || model.isSequencing)
      .help(revertWithoutCommittingHelp)
    }
  }

  private func cherryPickOptionsMenu(_ commits: [Commit]) -> some View {
    Menu("More Cherry-Pick Options") {
      Button("Cherry-Pick and Note the Source Commit") {
        Task { await model.cherryPick(commits, recordsOrigin: true) }
      }
      .help("Add “(cherry picked from commit …)” to the message, as backports usually do")
      Button("Apply Changes Without Committing") {
        Task { await model.cherryPick(commits, commit: false) }
      }
      .help("Stage the changes so you can adjust them and commit yourself")
    }
    .disabled(model.isBusy || model.isSequencing)
  }

  /// Reverts right away, or asks first when a merge is among `commits`.
  private func revert(_ commits: [Commit], commit: Bool) {
    if commits.contains(where: \.isMerge) {
      revertingWithMerge = PendingRevert(commits: commits, commit: commit)
    } else {
      Task { await model.revert(commits, commit: commit) }
    }
  }

  private var revertWithoutCommittingHelp: String {
    "Stage the inverse changes so you can adjust them and commit yourself"
  }

  private var mergeHelp: String {
    "A merge commit applies the changes it brought into its first parent"
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
  @State private var sign = false
  /// `nil` until loaded, or when git config can't be read.
  @State private var signing: CommitSigningConfiguration?

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
        TextField(
          "Message", text: $message,
          prompt: Text(sign ? "Optional; the tag name if empty" : "Optional; makes it annotated"))
        Toggle("Sign tag", isOn: $sign)
          .disabled(signing?.canSign == false && !sign)
          .help(signingHelp)
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
    .task {
      signing = await model.commitSigningConfiguration()
      sign = signing?.signsTagsByDefault ?? false
    }
  }

  private var signingHelp: String {
    guard let signing else { return "Sign the tag with your configured key" }
    guard signing.canSign else {
      return "Set user.signingKey to sign tags with \(signing.format.displayName)"
    }
    let key = signing.key.map { " \($0)" } ?? ""
    let prefix = signing.signsTagsByDefault ? "Signed by default (tag.gpgSign). " : ""
    return "\(prefix)Sign the tag with your \(signing.format.displayName) key\(key); signed tags are annotated"
  }

  /// Passes the choice to git only where it differs from `tag.gpgSign`.
  private var tagSigning: TagSigning {
    let signsByDefault = signing?.signsTagsByDefault ?? false
    return sign == signsByDefault ? .configured : sign ? .sign : .doNotSign
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
    let signing = tagSigning
    dismiss()
    Task {
      await model.createTag(
        name: tagName,
        at: commit.oid,
        message: trimmedMessage.isEmpty ? nil : trimmedMessage,
        signing: signing,
        pushToRemotes: pushToRemotes
      )
    }
  }
}
