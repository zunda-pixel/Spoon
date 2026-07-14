import SpoonCore
import SwiftUI

/// Content column for a selected remote: URLs, actions, and branch metadata.
@MainActor
struct RemoteDetailView: View {
  let model: RepositoryModel
  let remoteName: String

  @State private var showingEditSheet = false
  @Environment(\.openURL) private var openURL

  private var remote: Remote? {
    model.remotes.first { $0.name == remoteName }
  }

  private var branchCount: Int {
    model.remoteBranchesByRemote[remoteName]?.count ?? 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(remoteName, systemImage: "network")
        .font(.title2)

      if let remote {
        LabeledContent("Fetch URL") {
          Text(remote.fetchURL)
            .font(.callout.monospaced())
            .textSelection(.enabled)
        }
        if let pushURL = remote.pushURL {
          LabeledContent("Push URL") {
            Text(pushURL)
              .font(.callout.monospaced())
              .textSelection(.enabled)
          }
        }
        LabeledContent("Remote Branches", value: branchCount, format: .number)

        HStack {
          if let repoRef = RemoteURLParser.gitHubRepo(from: remote.fetchURL),
            let url = URL(string: "https://github.com/\(repoRef.slug)")
          {
            Button {
              openURL(url)
            } label: {
              Label("Open on GitHub", systemImage: "safari")
            }
          }
          Button("Edit URLs…", systemImage: "pencil") {
            showingEditSheet = true
          }
          .disabled(model.isBusy)
        }
        .controlSize(.small)
      } else {
        ContentUnavailableView(
          "Remote Not Found",
          systemImage: "network.slash"
        )
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(16)
    .sheet(isPresented: $showingEditSheet) {
      if let remote {
        EditRemoteSheet(model: model, remote: remote)
      }
    }
  }
}
