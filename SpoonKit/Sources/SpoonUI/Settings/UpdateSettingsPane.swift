import AppKit
import MacAppSettingsUI
import SpoonCore

/// The running version, the launch-time check, and a manual check that
/// opens the Software Update window.
@MainActor
final class UpdateSettingsPane: SettingsPaneViewController {
  private let appModel: AppModel
  private let openSoftwareUpdate: () -> Void

  init(appModel: AppModel, openSoftwareUpdate: @escaping () -> Void) {
    self.appModel = appModel
    self.openSoftwareUpdate = openSoftwareUpdate
    super.init(nibName: nil, bundle: nil)
    tabName = String(localized: "Updates")
    tabImage = NSImage(systemSymbolName: "arrow.down.app", accessibilityDescription: nil)
    tabIdentifier = "updates"
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func loadView() {
    view = NSView()
  }

  override func buildPaneContent() {
    // A pane can be built again after a cancelled load.
    view.subviews.forEach { $0.removeFromSuperview() }

    let layoutView = SettingsLayoutView()
    layoutView.install(in: view)

    let version = layoutView.addColumnSection(
      label: String(localized: "Current version"),
      itemColumnMaximumWidth: 300,
      identifier: .init("Version")
    )
    version.addCustomView(
      NSTextField(
        labelWithString: appModel.updater.currentVersion?.description
          ?? String(localized: "Development build")))

    let check = layoutView.addColumnSection(
      label: String(localized: "Check"),
      identifier: .init("Check")
    )
    check.addCheckbox(
      title: String(localized: "Check for updates when Spoon opens"),
      isOn: appModel.updater.automaticallyChecks,
      target: self,
      action: #selector(toggleAutomaticChecks(_:))
    )
    check.addButton(title: String(localized: "Check Now"), target: self, action: #selector(checkNow))
    check.addDescriptionLabel(String(localized: "Updates are downloaded from the project’s GitHub releases."))

    sizePaneToFitContent(minimumWidth: 520)
  }

  @objc private func toggleAutomaticChecks(_ sender: NSButton) {
    appModel.updater.automaticallyChecks = sender.state == .on
  }

  @objc private func checkNow() {
    openSoftwareUpdate()
    Task { await appModel.updater.checkForUpdates() }
  }
}
