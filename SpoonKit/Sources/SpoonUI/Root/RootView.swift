public import SpoonCore
public import SwiftUI
import os

let uiLogger = Logger(subsystem: "com.spoon.app", category: "ui")

/// Window content for `WindowGroup(for: Repository.ID.self)`:
/// no value → Welcome, value → that repository.
@MainActor
public struct RootView: View {
  @Binding private var repositoryID: Repository.ID?
  @Environment(AppModel.self) private var appModel

  public init(repositoryID: Binding<Repository.ID?>) {
    self._repositoryID = repositoryID
  }

  public var body: some View {
    Group {
      if let repositoryID {
        RepositoryWindowRoot(
          repositoryID: repositoryID,
          switchRepository: { self.repositoryID = $0 }
        )
      } else {
        WelcomeView { repositoryID = $0 }
      }
    }
    .task {
      uiLogger.info("RootView appeared, repositoryID=\(repositoryID ?? "nil", privacy: .public)")
      consumeExternalOpenRequest()
    }
    .onChange(of: appModel.externalOpenRequest) {
      consumeExternalOpenRequest()
    }
    // SwiftUI's lifecycle delivers Finder/`open` file events here, not to
    // NSApplicationDelegate.application(_:open:).
    .onOpenURL { url in
      guard url.isFileURL else { return }
      appModel.submitExternalOpenRequest(url)
    }
  }

  /// Folders arriving from Finder / `open -a Spoon <dir>`. Every open
  /// window observes the request; `takeExternalOpenRequest` hands it to
  /// exactly one of them.
  private func consumeExternalOpenRequest() {
    guard let url = appModel.takeExternalOpenRequest() else { return }
    uiLogger.info("consuming external open request: \(url.path, privacy: .public)")
    Task {
      do {
        let repository = try await appModel.openRepository(at: url)
        uiLogger.info("opened repository \(repository.id, privacy: .public)")
        if repositoryID == nil {
          repositoryID = repository.id
        } else if repositoryID != repository.id {
          openWindow(value: repository.id)
        }
      } catch {
        uiLogger.error("open failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  @Environment(\.openWindow) private var openWindow
}
