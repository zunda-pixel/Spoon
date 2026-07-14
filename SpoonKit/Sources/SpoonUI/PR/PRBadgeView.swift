import SpoonCore
import SwiftUI

/// Compact PR indicator on a branch row: number, CI rollup dot, and
/// review state.
@MainActor
struct PRBadgeView: View {
  let pullRequest: PullRequest

  var body: some View {
    Group {
      if let url = URL(string: pullRequest.url) {
        Link(destination: url) {
          badgeContent
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the pull request in your browser")
      } else {
        badgeContent
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Pull request \(pullRequest.number)")
    .accessibilityValue(accessibilityValue)
  }

  private var badgeContent: some View {
    HStack(spacing: 3) {
      if let checksState = pullRequest.checksState {
        Circle()
          .fill(checksColor(checksState))
          .frame(width: 7, height: 7)
          .help(checksHelp(checksState))
      }
      Text("#\(pullRequest.number)")
        .font(.caption.monospacedDigit())
      reviewIcon
    }
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .background(.quaternary, in: Capsule())
    .help(pullRequest.title)
  }

  private var accessibilityValue: String {
    var values = [pullRequest.isDraft ? "Draft" : "Open", pullRequest.title]
    if let checksState = pullRequest.checksState {
      values.append(checksHelp(checksState))
    }
    switch pullRequest.reviewDecision {
    case .approved:
      values.append("Approved")
    case .changesRequested:
      values.append("Changes requested")
    case .reviewRequired:
      values.append("Review required")
    case nil:
      break
    }
    return values.joined(separator: ", ")
  }

  @ViewBuilder
  private var reviewIcon: some View {
    switch pullRequest.reviewDecision {
    case .approved:
      Image(systemName: "checkmark.seal.fill")
        .font(.caption2)
        .foregroundStyle(.green)
        .help("Approved")
    case .changesRequested:
      Image(systemName: "exclamationmark.bubble.fill")
        .font(.caption2)
        .foregroundStyle(.orange)
        .help("Changes requested")
    case .reviewRequired, nil:
      EmptyView()
    }
  }

  private func checksColor(_ state: ChecksState) -> Color {
    if state.isFailure { return .red }
    if state.isRunning { return .yellow }
    return .green
  }

  private func checksHelp(_ state: ChecksState) -> String {
    if state.isFailure { return "Checks failing" }
    if state.isRunning { return "Checks running" }
    return "Checks passing"
  }
}

@MainActor
struct PRNumberLink: View {
  let pullRequest: PullRequest

  var body: some View {
    if let url = URL(string: pullRequest.url) {
      Link("#\(pullRequest.number)", destination: url)
        .buttonStyle(.plain)
        .help("Open pull request \(pullRequest.number) on GitHub")
        .accessibilityHint("Opens the pull request in your browser")
    } else {
      Text("#\(pullRequest.number)")
    }
  }
}
