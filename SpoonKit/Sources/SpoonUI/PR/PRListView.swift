import SpoonCore
import SwiftUI

@MainActor
struct PRListView: View {
  let model: RepositoryModel
  @Binding var selectedPRNumber: Int?

  init(model: RepositoryModel, selectedPRNumber: Binding<Int?>) {
    self.model = model
    self._selectedPRNumber = selectedPRNumber
  }

  var body: some View {
    Group {
      switch model.prSyncState {
      case .unauthenticated:
        ContentUnavailableView(
          "Not Signed In to GitHub",
          systemImage: "person.crop.circle.badge.questionmark",
          description: Text("Run `gh auth login` in Terminal, or add a token in Settings → GitHub.")
        )
      case .noGitHubRemote:
        ContentUnavailableView(
          "No GitHub Remote",
          systemImage: "network.slash",
          description: Text("This repository has no GitHub remote.")
        )
      case .rateLimited:
        ContentUnavailableView(
          "PR Data Paused",
          systemImage: "hourglass",
          description: Text("GitHub rate limit reached — syncing resumes automatically.")
        )
      case .failed(let message):
        ContentUnavailableView(
          "Could Not Load Pull Requests",
          systemImage: "exclamationmark.triangle",
          description: Text(message)
        )
      case .idle, .syncing, .synced:
        if model.openPullRequests.isEmpty {
          if case .syncing = model.prSyncState {
            ProgressView()
          } else {
            ContentUnavailableView(
              "No Open Pull Requests",
              systemImage: "checkmark.circle",
              description: Text("All quiet on \(model.gitHubRepoRef?.slug ?? "GitHub").")
            )
          }
        } else {
          List(selection: $selectedPRNumber) {
            ForEach(model.openPullRequests) { pullRequest in
              PRRowView(pullRequest: pullRequest)
                .tag(pullRequest.number)
            }
          }
        }
      }
    }
  }
}

@MainActor
struct PRRowView: View {
  let pullRequest: PullRequest

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        if pullRequest.isDraft {
          Text("Draft")
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
        }
        Text(pullRequest.title)
          .fontWeight(.medium)
          .lineLimit(1)
      }
      HStack(spacing: 6) {
        Text("#\(pullRequest.number)")
          .monospacedDigit()
        if let author = pullRequest.authorLogin {
          Text(author)
        }
        Text("\(pullRequest.baseRefName) ← \(pullRequest.headRefName)")
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}
