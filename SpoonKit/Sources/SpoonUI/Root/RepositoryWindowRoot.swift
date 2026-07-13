import SpoonCore
import SwiftUI

@MainActor
struct RepositoryWindowRoot: View {
  let repositoryID: Repository.ID

  @Environment(AppModel.self) private var appModel
  @State private var model: RepositoryModel?
  @State private var loadErrorMessage: String?

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
    .navigationTitle(Repository(rootURL: repositoryURL).name)
  }

  private var repositoryURL: URL {
    URL(filePath: repositoryID, directoryHint: .isDirectory)
  }

  private func load() async {
    do {
      let model = try await appModel.makeRepositoryModel(for: Repository(rootURL: repositoryURL))
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
  @State private var navigation = RepositoryNavigationState()

  var body: some View {
    NavigationSplitView {
      RepoSidebarView(model: model, navigation: navigation)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } content: {
      RepositoryContentColumn(model: model, navigation: navigation)
        .navigationSplitViewColumnWidth(min: 300, ideal: 380)
    } detail: {
      RepositoryDetailColumn(model: model, navigation: navigation)
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if let state = model.sequencerState {
        SequencerBannerView(model: model, state: state)
      }
    }
    .navigationTitle(model.repository.name)
    .navigationSubtitle(sectionTitle)
    .navigationDocument(model.repository.rootURL)
    .toolbar {
      RepositoryToolbar(model: model, navigation: navigation)
    }
    .repositorySheets(model: model, navigation: navigation)
    .confirmationDialog(
      "Force push \(model.currentBranch?.name ?? "the current branch")?",
      isPresented: .init(
        get: { navigation.confirmation == .forcePush },
        set: { if !$0 { navigation.confirmation = nil } }
      )
    ) {
      Button("Force Push with Lease", role: .destructive) {
        Task { await model.push(force: true) }
      }
    } message: {
      Text(
        "This rewrites the remote branch history. The push will be refused if the remote changed since your last fetch."
      )
    }
    .confirmationDialog(
      "Abort \(sequencerName)?",
      isPresented: .init(
        get: { navigation.confirmation == .abortSequencer },
        set: { if !$0 { navigation.confirmation = nil } }
      )
    ) {
      Button("Abort \(sequencerName)", role: .destructive) {
        Task { await model.abortSequencer() }
      }
    } message: {
      Text("All progress from this operation will be discarded and the branch restored.")
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
    .focusedSceneValue(\.repositoryModel, model)
    .focusedSceneValue(\.repositoryNavigationState, navigation)
  }

  private var sectionTitle: String {
    switch navigation.sidebarSelection {
    case .changes, nil: "Changes"
    case .history: "History"
    case .reflog: "Reflog"
    case .branch(let name): name
    case .pullRequests: "Pull Requests"
    case .remote(let name): name
    case .stash(let index): "stash@{\(index)}"
    }
  }

  private var sequencerName: String {
    switch model.sequencerState?.kind {
    case .rebase: "Rebase"
    case .cherryPick: "Cherry-Pick"
    case .revert: "Revert"
    case .merge: "Merge"
    case nil: "Operation"
    }
  }
}
