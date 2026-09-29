import AppKit
import SpoonCore
public import SwiftUI

/// Scene identifier of the single Software Update window.
public let softwareUpdateWindowID = "software-update"

/// Contents of the Software Update window: check progress, the available
/// release with its notes, and install / skip / later actions.
public struct SoftwareUpdateView: View {
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openURL) private var openURL

  public init() {}

  private var updater: AppUpdater { appModel.updater }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 64, height: 64)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.title3.bold())
          Text(subtitle)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      content
    }
    .padding(20)
    .frame(width: 620)
    .frame(minHeight: 160)
  }

  @ViewBuilder
  private var content: some View {
    switch updater.state {
    case .checking:
      ProgressView("Checking for updates…")
        .frame(maxWidth: .infinity)
    case .available(let release):
      releaseNotes(release)
      HStack {
        Button("Skip This Version") {
          updater.skip(release)
          dismissWindow(id: softwareUpdateWindowID)
        }
        Button("View on GitHub") { openURL(release.pageURL) }
        Spacer()
        Button("Remind Me Later") {
          updater.dismiss()
          dismissWindow(id: softwareUpdateWindowID)
        }
        .keyboardShortcut(.cancelAction)
        Button("Install and Relaunch") {
          Task {
            await updater.install(release)
            if case .readyToRelaunch = updater.state {
              AppRelauncher.relaunch(updater.appURL)
            }
          }
        }
        .keyboardShortcut(.defaultAction)
      }
      // Keep every button label whole rather than truncating it.
      .fixedSize(horizontal: false, vertical: true)
    case .installing:
      ProgressView("Downloading and installing…")
        .frame(maxWidth: .infinity)
    case .readyToRelaunch:
      HStack {
        Spacer()
        Button("Relaunch Now") { AppRelauncher.relaunch(updater.appURL) }
          .keyboardShortcut(.defaultAction)
      }
    case .idle, .upToDate, .failed:
      HStack {
        Spacer()
        if case .failed = updater.state {
          Button("Try Again") { Task { await updater.checkForUpdates() } }
        }
        Button("OK") {
          updater.dismiss()
          dismissWindow(id: softwareUpdateWindowID)
        }
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  private func releaseNotes(_ release: AppRelease) -> some View {
    ScrollView {
      Text(notes(release))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(10)
    }
    .frame(height: 200)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    .accessibilityLabel("Release notes")
  }

  private func notes(_ release: AppRelease) -> AttributedString {
    let text = release.notes.isEmpty ? "No release notes." : release.notes
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }

  private var current: String {
    updater.currentVersion?.description ?? "a development build"
  }

  private var title: String {
    switch updater.state {
    case .checking: "Checking for Updates"
    case .available(let release), .installing(let release):
      "Spoon \(release.version.description) Is Available"
    case .readyToRelaunch(let release): "Spoon \(release.version.description) Is Installed"
    case .upToDate: "Spoon Is Up to Date"
    case .failed: "Couldn’t Check for Updates"
    case .idle: "Software Update"
    }
  }

  private var subtitle: String {
    switch updater.state {
    case .checking: "Looking for a newer release on GitHub."
    case .available: "You have \(current). Install the new version now?"
    case .installing: "Spoon will relaunch when the new version is in place."
    case .readyToRelaunch: "Relaunch Spoon to start using the new version."
    case .upToDate: "You have \(current), the newest release."
    case .failed(let message): message
    case .idle: "You have \(current)."
    }
  }
}

/// Reopens the app after it quits, so a replaced bundle starts fresh.
@MainActor
enum AppRelauncher {
  static func relaunch(_ appURL: URL) {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    // Wait for this process to exit, then open the new bundle.
    process.arguments = [
      "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
      "spoon-relaunch", String(ProcessInfo.processInfo.processIdentifier), appURL.path,
    ]
    do {
      try process.run()
      NSApp.terminate(nil)
    } catch {
      NSWorkspace.shared.open(appURL)
    }
  }
}
