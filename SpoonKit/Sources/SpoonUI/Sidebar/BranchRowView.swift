import SpoonCore
import SwiftUI

@MainActor
struct BranchRowView: View {
  let branch: Branch
  var displayName: String?
  var pullRequest: PullRequest?
  var worktree: Worktree?
  var showsTrackingStatus = true

  var body: some View {
    Label {
      HStack(spacing: 4) {
        Text(displayName ?? branch.name)
          .fontWeight(branch.isCurrent ? .semibold : .regular)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        if let pullRequest {
          PRBadgeView(pullRequest: pullRequest)
        }
        if let worktree {
          Image(systemName: "folder")
            .foregroundStyle(.secondary)
            .help("Checked out in worktree: \(worktree.path.path)")
        }
        if showsTrackingStatus {
          trackingIndicator
        }
      }
    } icon: {
      Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.trianglehead.branch")
        .foregroundStyle(branch.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }
    .help(branch.subject)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(branch.name)
    .accessibilityValue(accessibilityValue)
    .accessibilityHint(
      "Select to move to this branch in history; open the context menu for branch actions")
  }

  private var accessibilityValue: String {
    var values = [showsTrackingStatus ? "Local branch" : "Remote branch"]
    if branch.isCurrent {
      values.append("Current branch")
    }
    if showsTrackingStatus {
      if branch.upstreamGone {
        values.append("Upstream branch is gone")
      } else if let upstream = branch.upstream {
        values.append("Tracks \(upstream)")
        if let ahead = branch.ahead, ahead > 0 {
          values.append("\(ahead) commit(s) ahead")
        }
        if let behind = branch.behind, behind > 0 {
          values.append("\(behind) commit(s) behind")
        }
      } else {
        values.append("No remote branch linked")
      }
    }
    if let worktree {
      values.append("Checked out in worktree at \(worktree.path.path)")
    }
    if let pullRequest {
      values.append(
        pullRequest.isDraft
          ? "Draft pull request \(pullRequest.number)"
          : "Open pull request \(pullRequest.number)"
      )
    }
    return values.joined(separator: ", ")
  }

  @ViewBuilder
  private var trackingIndicator: some View {
    if branch.upstreamGone {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .help("Upstream branch is gone")
    } else if let upstream = branch.upstream {
      HStack(spacing: 2) {
        if pullRequest == nil {
          Image(systemName: "link")
        }
        if let ahead = branch.ahead, ahead > 0 {
          Text("↑\(ahead)")
        }
        if let behind = branch.behind, behind > 0 {
          Text("↓\(behind)")
        }
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      .help("Tracking \(upstream)")
    }
  }
}
