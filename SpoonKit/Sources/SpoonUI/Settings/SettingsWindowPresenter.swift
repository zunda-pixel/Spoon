import AppKit
import MacAppSettingsUI
public import SpoonCore

/// The ⌘, window, built with MacAppSettingsUI: a preferences-style toolbar
/// with one pane per tab. Created on first use and kept for the app's life,
/// so the frame and the last selected tab carry over between openings.
@MainActor
public final class SettingsWindowPresenter {
  public static let shared = SettingsWindowPresenter()

  private var controller: SettingsWindowController?

  private init() {}

  /// Shows the window, building it the first time.
  /// `openSoftwareUpdate` opens the SwiftUI Software Update window, which
  /// this AppKit window can't reach through `openWindow` itself.
  public func show(appModel: AppModel, openSoftwareUpdate: @escaping () -> Void) {
    let controller =
      controller ?? makeController(appModel: appModel, openSoftwareUpdate: openSoftwareUpdate)
    self.controller = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private func makeController(
    appModel: AppModel, openSoftwareUpdate: @escaping () -> Void
  ) -> SettingsWindowController {
    let controller = SettingsWindowController(with: [
      GitHubSettingsPane(),
      UpdateSettingsPane(appModel: appModel, openSoftwareUpdate: openSoftwareUpdate),
      LicensesSettingsPane(),
    ])
    controller.restoresLastSelectedTab = true
    return controller
  }
}
