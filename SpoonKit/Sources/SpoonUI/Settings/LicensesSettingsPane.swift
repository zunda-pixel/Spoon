import AppKit
import MacAppSettingsUI
import SwiftUI

/// The licenses of the packages Spoon is built with, generated at build
/// time by LicenseProvider.
@MainActor
final class LicensesSettingsPane: SettingsPaneViewController {
  private static let defaultPaneSize = NSSize(width: 680, height: 460)

  init() {
    super.init(nibName: nil, bundle: nil)
    tabName = String(localized: "Licenses")
    tabImage = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
    tabIdentifier = "licenses"
    isResizableView = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func loadView() {
    view = NSView(frame: NSRect(origin: .zero, size: Self.defaultPaneSize))
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
      view.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
    ])
  }

  override func buildPaneContent() {
    // A pane can be built again after a cancelled load.
    view.subviews.forEach { $0.removeFromSuperview() }

    let hostingView = NSHostingView(rootView: LicensesView(packages: LicenseProvider.packages))
    hostingView.sizingOptions = []
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: view.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    // Switching tabs hands over the previous pane's frame, so the size is
    // declared again.
    view.setFrameSize(Self.defaultPaneSize)
    capturePreferredPaneSize()
  }
}

/// Package names on the left, the selected one's license on the right.
@MainActor
private struct LicensesView: View {
  let packages: [Package]
  @State private var selection: Package.ID?

  var body: some View {
    HSplitView {
      List(packages, selection: $selection) { package in
        Text(package.name)
      }
      .frame(minWidth: 180, idealWidth: 200, maxWidth: 280)

      Group {
        if let package = packages.first(where: { $0.id == selection }) {
          detail(package)
        } else {
          ContentUnavailableView(
            "Select a Package",
            systemImage: "doc.text",
            description: Text("\(packages.count) open source packages are part of Spoon.")
          )
        }
      }
      .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear { selection = selection ?? packages.first?.id }
  }

  private func detail(_ package: Package) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(package.name)
          .font(.headline)
        Spacer()
        if case .remoteSourceControl(let location) = package.kind {
          Link("Open Repository", destination: location)
        }
      }
      .padding(12)
      Divider()
      ScrollView {
        // The generated text indents its first line.
        Text(package.license.trimmingCharacters(in: .whitespacesAndNewlines))
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
    }
  }
}
