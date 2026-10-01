import AppKit
import MacAppSettingsUI
import SpoonCore

/// GitHub sign-in: the GitHub CLI login is used when there is one, and a
/// personal access token saved to the Keychain is the fallback.
@MainActor
final class GitHubSettingsPane: SettingsPaneViewController {
  private let tokenField = NSSecureTextField()
  private var statusLabel: SettingsWrappingLabel?

  init() {
    super.init(nibName: nil, bundle: nil)
    tabName = String(localized: "GitHub")
    tabImage = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)
    tabIdentifier = "github"
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

    let signIn = layoutView.addColumnSection(
      label: String(localized: "Preferred sign-in"),
      itemColumnMaximumWidth: 300,
      identifier: .init("SignIn")
    )
    signIn.addCustomView(NSTextField(labelWithString: String(localized: "GitHub CLI (gh auth login)")))
    signIn.addDescriptionLabel(
      String(
        localized:
          "Spoon reuses your GitHub CLI login automatically. If you don’t use gh, paste a personal access token below (repo scope)."
      ))

    layoutView.addSeparatorSection()

    let token = layoutView.addColumnSection(
      label: String(localized: "Access token"),
      identifier: .init("Token")
    )
    tokenField.placeholderString = "ghp_…"
    tokenField.stringValue = KeychainTokenProvider.storedToken() ?? ""
    tokenField.widthAnchor.constraint(equalToConstant: 260).isActive = true
    token.addCustomView(tokenField)
    token.addButton(title: String(localized: "Save to Keychain"), target: self, action: #selector(save))
    statusLabel = token.addDescriptionLabel(Self.storedStatus)

    sizePaneToFitContent(minimumWidth: 520)
  }

  private static var storedStatus: String {
    KeychainTokenProvider.storedToken() == nil
      ? String(localized: "No token is saved. Spoon uses the GitHub CLI login.")
      : String(localized: "A token is saved in the Keychain.")
  }

  @objc private func save() {
    let token = tokenField.stringValue.trimmingCharacters(in: .whitespaces)
    do {
      try KeychainTokenProvider.save(token: token)
      statusLabel?.stringValue = token.isEmpty ? String(localized: "Token removed.") : String(localized: "Saved.")
    } catch {
      statusLabel?.stringValue = String(localized: "Could not save: \(error.localizedDescription)")
    }
    invalidatePaneSize()
  }
}
