import SpoonCore
import SwiftUI

@MainActor
struct FileHistorySheet: View {
  let model: RepositoryModel
  let path: String
  @Environment(\.dismiss) private var dismiss
  @State private var commits: [Commit]?
  @State private var selectedCommitID: String?
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("History — \(path)")
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      Divider()

      NavigationSplitView {
        content
          .navigationSplitViewColumnWidth(min: 280, ideal: 340)
      } detail: {
        if let selectedCommitID, let oid = ObjectID(rawValue: selectedCommitID) {
          CommitDetailView(model: model, oid: oid)
        } else {
          ContentUnavailableView(
            "No Commit Selected",
            systemImage: "clock",
            description: Text("Select a commit to inspect its changes.")
          )
        }
      }
    }
    .frame(minWidth: 760, minHeight: 480)
    .task(id: path) {
      do {
        let page = try await model.fileHistory(
          LogQuery(path: path, maxCount: 1_000)
        )
        commits = page.commits
        selectedCommitID = page.commits.first?.id
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let commits {
      if commits.isEmpty {
        ContentUnavailableView(
          "No File History",
          systemImage: "clock",
          description: Text("No commits include this path.")
        )
      } else {
        List(commits, selection: $selectedCommitID) { commit in
          VStack(alignment: .leading, spacing: 2) {
            Text(commit.subject)
              .lineLimit(1)
            HStack {
              Text(commit.oid.shortened)
                .font(.caption.monospaced())
              Text(commit.committedAt, format: .relative(presentation: .named))
                .font(.caption)
            }
            .foregroundStyle(.secondary)
          }
          .tag(commit.id)
        }
        .listStyle(.plain)
      }
    } else if let errorMessage {
      ContentUnavailableView(
        "Could Not Load File History",
        systemImage: "exclamationmark.triangle",
        description: Text(errorMessage)
      )
    } else {
      ProgressView()
    }
  }
}
