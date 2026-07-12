import SpoonCore
import SwiftUI

/// Content column for a selected remote: its URLs and remote-tracking
/// branches.
@MainActor
struct RemoteDetailView: View {
  let model: RepositoryModel
  let remoteName: String

  @State private var branches: [Branch]?
  @State private var errorMessage: String?
  @Environment(\.openURL) private var openURL

  init(model: RepositoryModel, remoteName: String) {
    self.model = model
    self.remoteName = remoteName
  }

  private var remote: Remote? {
    model.remotes.first { $0.name == remoteName }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      branchList
    }
    .task(id: remoteName) {
      do {
        errorMessage = nil
        branches = try await model.remoteBranches(of: remoteName)
      } catch {
        branches = nil
        errorMessage = error.localizedDescription
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(remoteName, systemImage: "network")
        .font(.headline)
      if let remote {
        Text(remote.fetchURL)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .lineLimit(1)
          .truncationMode(.middle)
        if let pushURL = remote.pushURL {
          Text("push: \(pushURL)")
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        if let repoRef = RemoteURLParser.gitHubRepo(from: remote.fetchURL),
          let url = URL(string: "https://github.com/\(repoRef.slug)")
        {
          Button {
            openURL(url)
          } label: {
            Label("Open on GitHub", systemImage: "safari")
          }
          .controlSize(.small)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
  }

  @ViewBuilder
  private var branchList: some View {
    if let branches {
      if branches.isEmpty {
        ContentUnavailableView(
          "No Remote Branches",
          systemImage: "arrow.trianglehead.branch",
          description: Text("Fetch to see this remote's branches.")
        )
      } else {
        List(branches) { branch in
          Label {
            HStack {
              Text(branch.name)
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer(minLength: 4)
              if let committedAt = branch.committedAt {
                Text(committedAt, format: .relative(presentation: .named))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } icon: {
            Image(systemName: "arrow.trianglehead.branch")
              .foregroundStyle(.secondary)
          }
          .help(branch.subject)
        }
        .listStyle(.plain)
      }
    } else if let errorMessage {
      ContentUnavailableView(
        "Could Not Load Remote Branches",
        systemImage: "exclamationmark.triangle",
        description: Text(errorMessage)
      )
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
