import SpoonCore
import SwiftUI

@MainActor
struct PRDetailView: View {
  let pullRequest: PullRequest
  @Environment(\.openURL) private var openURL

  init(pullRequest: PullRequest) {
    self.pullRequest = pullRequest
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            if pullRequest.isDraft {
              chip("Draft", systemImage: "pencil.circle", tint: .secondary)
            }
            chip("#\(pullRequest.number)", systemImage: "arrow.triangle.pull", tint: .green)
          }
          Text(pullRequest.title)
            .font(.title2.bold())
            .textSelection(.enabled)
          Text("\(pullRequest.baseRefName) ← \(pullRequest.headRefName)")
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
        }

        Divider()

        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
          if let author = pullRequest.authorLogin {
            GridRow {
              Text("Author").foregroundStyle(.secondary)
              Text(author)
            }
          }
          GridRow {
            Text("Review").foregroundStyle(.secondary)
            reviewLabel
          }
          GridRow {
            Text("Checks").foregroundStyle(.secondary)
            checksLabel
          }
          if let updatedAt = pullRequest.updatedAt {
            GridRow {
              Text("Updated").foregroundStyle(.secondary)
              Text(updatedAt, format: .relative(presentation: .named))
            }
          }
        }
        .font(.callout)

        Divider()

        HStack {
          Button {
            if let url = URL(string: pullRequest.url) {
              openURL(url)
            }
          } label: {
            Label("Open on GitHub", systemImage: "safari")
          }

          // AI review lands in the next milestone; the seam is already here.
          Button {
          } label: {
            Label("Review with AI", systemImage: "sparkles")
          }
          .disabled(true)
          .help("AI review arrives in a later milestone")
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var reviewLabel: some View {
    switch pullRequest.reviewDecision {
    case .approved:
      Label("Approved", systemImage: "checkmark.seal.fill")
        .foregroundStyle(.green)
    case .changesRequested:
      Label("Changes requested", systemImage: "exclamationmark.bubble.fill")
        .foregroundStyle(.orange)
    case .reviewRequired:
      Label("Review required", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case nil:
      Label("No reviews", systemImage: "minus.circle")
        .foregroundStyle(.secondary)
    }
  }

  private var checksLabel: some View {
    Group {
      if let state = pullRequest.checksState {
        if state.isFailure {
          Label("Failing", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        } else if state.isRunning {
          Label("Running", systemImage: "circle.dotted").foregroundStyle(.yellow)
        } else {
          Label("Passing", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
      } else {
        Label("No checks", systemImage: "minus.circle").foregroundStyle(.secondary)
      }
    }
  }

  private func chip(_ text: String, systemImage: String, tint: Color) -> some View {
    Label(text, systemImage: systemImage)
      .font(.caption)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(.quaternary, in: Capsule())
      .foregroundStyle(tint)
  }
}
