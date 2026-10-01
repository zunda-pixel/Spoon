import AppKit
import MacAppSettingsUI

/// The ⌘, window, built with MacAppSettingsUI: a preferences-style toolbar
/// with one pane per tab. Created on first use and kept for the app's life,
/// so the frame and the last selected tab carry over between openings.
@MainActor
public final class SettingsWindowPresenter {
  public static let shared = SettingsWindowPresenter()

  private var controller: SettingsWindowController?

  private init() {}

  /// Shows the window, building it the first time.
  public func show() {
    let controller = controller ?? makeController()
    self.controller = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private func makeController() -> SettingsWindowController {
    let controller = SettingsWindowController(with: [
      GitHubSettingsPane()
    ])
    controller.restoresLastSelectedTab = true
    return controller
  }
}
