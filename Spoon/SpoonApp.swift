import AppKit
import SpoonCore
import SpoonUI
import SwiftUI
import os

@main
struct SpoonApp: App {
  @NSApplicationDelegateAdaptor(SpoonAppDelegate.self) private var appDelegate
  @State private var appModel: AppModel

  init() {
    let model = AppModel()
    // `Spoon.app/Contents/MacOS/Spoon /path/to/repo` and
    // `open -a Spoon --args /path/to/repo` (first launch).
    if let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
      model.submitExternalOpenRequest(URL(filePath: path, directoryHint: .isDirectory))
    }
    self._appModel = State(initialValue: model)
  }

  var body: some Scene {
    WindowGroup(for: Repository.ID.self) { $repositoryID in
      RootView(repositoryID: $repositoryID)
        .environment(appModel)
        .onAppear { appDelegate.appModel = appModel }
    }
    // Always present a window at launch; a delegate that implements
    // application(_:open:) otherwise suppresses the default window on
    // argument-carrying launches.
    .defaultLaunchBehavior(.presented)
    .commands {
      SpoonCommands()
    }

    Settings {
      SettingsView()
    }
  }
}

/// Receives folders from Finder / `open -a Spoon <dir>` and forwards them
/// into the SwiftUI world via AppModel.
final class SpoonAppDelegate: NSObject, NSApplicationDelegate {
  @MainActor var appModel: AppModel?

  private let logger = Logger(subsystem: "com.spoon.app", category: "open")

  func application(_ application: NSApplication, open urls: [URL]) {
    logger.info("application(_:open:) received \(urls.count) url(s): \(urls.first?.path ?? "-")")
    MainActor.assumeIsolated {
      guard let url = urls.first else { return }
      if appModel == nil {
        logger.error("appModel not wired yet; dropping open request")
      }
      appModel?.submitExternalOpenRequest(url)
    }
  }
}
