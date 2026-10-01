import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct RepositoryToolbar: ToolbarContent {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState
  @Environment(AppModel.self) private var appModel
  @Environment(\.openWindow) private var openWindow

  var body: some ToolbarContent {
    if let release = appModel.updater.availableRelease {
      ToolbarItem {
        Button {
          openWindow(id: softwareUpdateWindowID)
        } label: {
          Label("Update to \(release.version.description)", systemImage: "arrow.down.app.fill")
        }
        .help("Spoon \(release.version.description) is available")
        .accessibilityHint("Opens Software Update to install the new version")
      }
    }
    ToolbarItemGroup {
      Button {
        Task { await model.fetch() }
      } label: {
        Label("Fetch", systemImage: "arrow.down.circle")
      }
      .help("Fetch all remotes (⇧⌘F)")
      .accessibilityHint("Downloads updated references from all remotes")
      .disabled(model.isBusy)

      Menu {
        PullMenuItems(model: model)
      } label: {
        remoteCountLabel(
          "Pull", systemImage: "arrow.down.to.line", count: model.currentBranch?.behind)
      } primaryAction: {
        Task { await model.pull() }
      }
      .help("Pull (⇧⌘L); open the menu to rebase, merge, or fast-forward only")
      .accessibilityHint(
        "Fetches and integrates the current upstream branch; open the menu for other pull modes"
      )
      .disabled(model.isBusy || model.isSequencing)

      Menu {
        Button("Push") {
          Task { await model.push() }
        }
        Divider()
        Button("Force Push with Lease…", role: .destructive) {
          navigation.confirm(.forcePush)
        }
      } label: {
        remoteCountLabel("Push", systemImage: "arrow.up.to.line", count: model.currentBranch?.ahead)
      } primaryAction: {
        Task { await model.push() }
      }
      .help("Push (⇧⌘U); open the menu for force push")
      .accessibilityHint("Pushes the current branch; open the menu for force push")
      .disabled(model.isBusy || model.isSequencing)
    }
    ToolbarItemGroup {
      Menu {
        ForEach(AIProviderID.allCases) { provider in
          Button("Review with \(provider.displayName)") {
            Task {
              await model.runReview(with: provider)
              if let report = model.reviewReport {
                navigation.present(.review(report))
              }
            }
          }
        }
      } label: {
        Label(model.aiActivity == nil ? "AI Review" : "Reviewing…", systemImage: "sparkles")
      }
      .disabled(model.aiActivity != nil)
      .help("Review this branch with Claude Code or Codex")
      .accessibilityHint("Choose a coding agent to review this branch")
      .accessibilityValue(model.aiActivity == nil ? "Idle" : "Review in progress")

      // One item whose label changes: swapping the button for a separate
      // progress item on every refresh made AppKit rebuild and re-lay out
      // the whole toolbar, which stalled the window in large repositories.
      let isWorking = model.isBusy || model.isRefreshing || model.aiActivity != nil
      Button {
        Task { await model.refresh() }
      } label: {
        if isWorking {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Repository operation in progress")
        } else {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
      .keyboardShortcut("r", modifiers: .command)
      .disabled(isWorking)
      .accessibilityHint("Reloads repository status and related data")
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        NSWorkspace.shared.open(model.repository.rootURL)
      } label: {
        Label("Open Directory", systemImage: "folder")
      }
      .help("Open the repository directory in Finder")
      .accessibilityHint("Opens the repository directory in Finder")
    }
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
    .accessibilityValue(count.map { "\($0) commit(s)" } ?? "No divergence information")
  }
}
