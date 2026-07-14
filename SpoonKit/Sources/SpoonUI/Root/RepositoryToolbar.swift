import AppKit
import SpoonCore
import SwiftUI

@MainActor
struct RepositoryToolbar: ToolbarContent {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState

  var body: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      branchMenu
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

      Button {
        Task { await model.pull() }
      } label: {
        remoteCountLabel(
          "Pull", systemImage: "arrow.down.to.line", count: model.currentBranch?.behind)
      }
      .help("Pull (⇧⌘L)")
      .accessibilityHint("Fetches and integrates the current upstream branch")
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

      if model.isBusy || model.isRefreshing || model.aiActivity != nil {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Repository operation in progress")
      }
      Button {
        Task { await model.refresh() }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .keyboardShortcut("r", modifiers: .command)
      .accessibilityHint("Reloads repository status and related data")
      .disabled(model.isRefreshing)
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

  private var branchMenu: some View {
    Menu {
      ForEach(model.branches) { branch in
        Button {
          Task { await model.checkout(branch: branch.name) }
        } label: {
          if branch.isCurrent {
            Label(branch.name, systemImage: "checkmark")
          } else {
            Text(branch.name)
          }
        }
        .disabled(branch.isCurrent)
      }
      Divider()
      Button("New Branch…") {
        navigation.present(.newBranch(startPoint: nil))
      }
    } label: {
      Label(
        model.currentBranch?.name ?? model.status?.headBranch ?? "detached HEAD",
        systemImage: "arrow.trianglehead.branch"
      )
      .labelStyle(.titleAndIcon)
    }
    .disabled(model.isBusy || model.isSequencing)
    .accessibilityLabel("Current branch")
    .accessibilityValue(model.currentBranch?.name ?? model.status?.headBranch ?? "Detached HEAD")
    .accessibilityHint("Choose a branch to check out or create a new branch")
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
