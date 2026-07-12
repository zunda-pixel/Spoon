import SpoonCore
import SwiftUI

enum SidebarItem: Hashable {
  case changes
  case history
  case branch(String)
  case pullRequests
  case remote(String)
  case stash(Int)
}

@MainActor
struct RepositoryWindowRoot: View {
  let repositoryID: Repository.ID

  @Environment(AppModel.self) private var appModel
  @State private var model: RepositoryModel?
  @State private var loadErrorMessage: String?

  init(repositoryID: Repository.ID) {
    self.repositoryID = repositoryID
  }

  var body: some View {
    Group {
      if let model {
        RepositorySplitView(model: model)
      } else if let loadErrorMessage {
        ContentUnavailableView(
          "Could Not Open Repository",
          systemImage: "exclamationmark.triangle",
          description: Text(loadErrorMessage)
        )
      } else {
        ProgressView()
          .task { await load() }
      }
    }
    .navigationTitle(Repository(rootURL: URL(filePath: repositoryID, directoryHint: .isDirectory)).name)
  }

  private func load() async {
    do {
      let repository = Repository(rootURL: URL(filePath: repositoryID, directoryHint: .isDirectory))
      let model = try await appModel.makeRepositoryModel(for: repository)
      await model.refresh()
      model.startWatching()
      self.model = model
    } catch {
      loadErrorMessage = error.localizedDescription
    }
  }
}

@MainActor
struct RepositorySplitView: View {
  let model: RepositoryModel
  @State private var selection: SidebarItem? = .changes
  @State private var selectedCommitID: String?
  @State private var fileSelections: Set<RepositoryModel.FileSelection> = []
  @State private var selectedPRNumber: Int?
  @State private var showingNewBranchSheet = false

  init(model: RepositoryModel) {
    self.model = model
  }

  var body: some View {
    NavigationSplitView {
      RepoSidebarView(model: model, selection: $selection)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } content: {
      contentColumn
        .navigationSplitViewColumnWidth(min: 300, ideal: 380)
    } detail: {
      detailColumn
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if let state = model.sequencerState {
        SequencerBannerView(model: model, state: state)
      }
    }
    // The window (and tab) title must identify the repository; the
    // section lives in the subtitle. Column-level navigationTitles would
    // otherwise take over the titlebar.
    .navigationTitle(model.repository.name)
    .navigationSubtitle(sectionTitle)
    .navigationDocument(model.repository.rootURL)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        branchMenu
      }
      ToolbarItemGroup {
        Button {
          Task { await model.fetch() }
        } label: {
          Label("Fetch", systemImage: "arrow.down.circle")
        }
        .help("Fetch all remotes (⇧⌘F)")
        .disabled(model.isBusy)

        Button {
          Task { await model.pull() }
        } label: {
          remoteCountLabel("Pull", systemImage: "arrow.down.to.line", count: model.currentBranch?.behind)
        }
        .help("Pull (⇧⌘L)")
        .disabled(model.isBusy || model.isSequencing)

        Button {
          Task { await model.push() }
        } label: {
          remoteCountLabel("Push", systemImage: "arrow.up.to.line", count: model.currentBranch?.ahead)
        }
        .help("Push (⇧⌘U)")
        .disabled(model.isBusy || model.isSequencing)
      }
      ToolbarItemGroup {
        Menu {
          ForEach(AIProviderID.allCases) { provider in
            Button("Review with \(provider.displayName)") {
              Task { await model.runReview(with: provider) }
            }
          }
        } label: {
          if case .reviewing = model.aiActivity {
            Label("Reviewing…", systemImage: "sparkles")
          } else {
            Label("AI Review", systemImage: "sparkles")
          }
        }
        .disabled(model.aiActivity != nil)
        .help("Review this branch with Claude Code or Codex")

        if model.isBusy || model.isRefreshing || model.aiActivity != nil {
          ProgressView()
            .controlSize(.small)
        }
        Button {
          Task { await model.refresh() }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(model.isRefreshing)
      }
    }
    .sheet(
      isPresented: .init(
        get: { model.reviewReport != nil },
        set: { if !$0 { model.dismissReview() } }
      )
    ) {
      if let report = model.reviewReport {
        ReviewFindingsView(report: report) {
          model.dismissReview()
        }
      }
    }
    .alert(
      "AI Task Failed",
      isPresented: .init(
        get: { model.aiErrorMessage != nil },
        set: { if !$0 { model.clearAIError() } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.aiErrorMessage ?? "")
    }
    .sheet(isPresented: $showingNewBranchSheet) {
      NewBranchSheet(model: model)
    }
    .focusedSceneValue(\.repositoryModel, model)
    .onChange(of: model.isNewBranchSheetRequested) {
      if model.isNewBranchSheetRequested {
        model.isNewBranchSheetRequested = false
        showingNewBranchSheet = true
      }
    }
    .alert(
      "Operation Failed",
      isPresented: .init(
        get: { model.lastErrorMessage != nil && model.status != nil },
        set: { if !$0 { model.clearError() } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.lastErrorMessage ?? "")
    }
  }

  private var branchMenu: some View {
    Menu {
      ForEach(model.branches) { branch in
        Button {
          Task { await model.checkout(branch: branch.name) }
        } label: {
          if branch.isCurrent {
            Label(branch.name, systemImage: "checkmark")
          } else {
            Text(branch.name)
          }
        }
        .disabled(branch.isCurrent)
      }
      Divider()
      Button("New Branch…") {
        showingNewBranchSheet = true
      }
    } label: {
      currentBranchLabel
    }
    .disabled(model.isBusy || model.isSequencing)
  }

  private func remoteCountLabel(_ title: String, systemImage: String, count: Int?) -> some View {
    HStack(spacing: 3) {
      Image(systemName: systemImage)
      if let count, count > 0 {
        Text("\(count)")
          .font(.caption.monospacedDigit())
      }
    }
    .accessibilityLabel(title)
  }

  private var sectionTitle: String {
    switch selection {
    case .changes, nil: "Changes"
    case .history: "History"
    case .branch(let name): name
    case .pullRequests: "Pull Requests"
    case .remote(let name): name
    case .stash(let index): "stash@{\(index)}"
    }
  }

  @ViewBuilder
  private var contentColumn: some View {
    switch selection {
    case .changes, nil:
      ChangesView(model: model, selection: $fileSelections)
    case .history, .branch:
      HistoryListView(model: model, selectedCommitID: $selectedCommitID)
    case .pullRequests:
      PRListView(model: model, selectedPRNumber: $selectedPRNumber)
    case .remote(let name):
      RemoteDetailView(model: model, remoteName: name)
    case .stash(let index):
      StashDetailView(model: model, stashIndex: index)
    }
  }

  @ViewBuilder
  private var detailColumn: some View {
    switch selection {
    case .changes, nil:
      if fileSelections.count == 1, let single = fileSelections.first {
        DiffDetailView(model: model, selection: single)
      } else if fileSelections.count > 1 {
        MultiSelectionActionsView(model: model, selections: fileSelections)
      } else {
        noSelectionPlaceholder
      }
    case .history, .branch:
      if let selectedCommitID, let oid = ObjectID(rawValue: selectedCommitID) {
        CommitDetailView(model: model, oid: oid)
      } else {
        noSelectionPlaceholder
      }
    case .pullRequests:
      if let selectedPRNumber,
        let pullRequest = model.openPullRequests.first(where: { $0.number == selectedPRNumber })
      {
        PRDetailView(pullRequest: pullRequest)
      } else {
        noSelectionPlaceholder
      }
    case .remote, .stash:
      noSelectionPlaceholder
    }
  }

  private var noSelectionPlaceholder: some View {
    ContentUnavailableView(
      "No Selection",
      systemImage: "doc.text.magnifyingglass",
      description: Text("Select a file or commit to see its changes.")
    )
  }

  private var currentBranchLabel: some View {
    Label(
      model.currentBranch?.name ?? model.status?.headBranch ?? "detached HEAD",
      systemImage: "arrow.trianglehead.branch"
    )
    .labelStyle(.titleAndIcon)
  }
}

/// Detail column for a multi-file selection: bulk stage/unstage actions.
@MainActor
private struct MultiSelectionActionsView: View {
  let model: RepositoryModel
  let selections: Set<RepositoryModel.FileSelection>

  var body: some View {
    let stageable = selections.filter { $0.area != .staged }
    let staged = selections.filter { $0.area == .staged }

    VStack(spacing: 14) {
      Image(systemName: "doc.on.doc")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("\(selections.count) files selected")
        .font(.title3)
      HStack {
        if !stageable.isEmpty {
          Button("Stage \(stageable.count) File(s)") {
            Task { await model.stage(paths: stageable.map(\.path)) }
          }
        }
        if !staged.isEmpty {
          Button("Unstage \(staged.count) File(s)") {
            Task { await model.unstage(paths: staged.map(\.path)) }
          }
        }
      }
      .disabled(model.isBusy)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
struct NewBranchSheet: View {
  let model: RepositoryModel
  /// Branch (or any ref) the new branch starts at; nil means HEAD.
  let startPoint: String?
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  init(model: RepositoryModel, startPoint: String? = nil) {
    self.model = model
    self.startPoint = startPoint
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(startPoint.map { "New Branch from \"\($0)\"" } ?? "New Branch")
        .font(.headline)
      TextField("Branch name", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit(create)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Button("Create and Checkout", action: create)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValidName)
      }
    }
    .padding(20)
  }

  private var isValidName: Bool {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return !trimmed.isEmpty && !trimmed.contains(" ") && !trimmed.hasPrefix("-")
  }

  private func create() {
    guard isValidName else { return }
    let branchName = name.trimmingCharacters(in: .whitespaces)
    dismiss()
    Task { await model.createBranch(name: branchName, from: startPoint, checkout: true) }
  }
}
