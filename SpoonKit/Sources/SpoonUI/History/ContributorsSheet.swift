import AppKit
import SpoonCore
import SwiftUI

/// Who authored the commits, with `.mailmap` folding each person's names
/// and addresses into one row (`git shortlog -sne`).
@MainActor
struct ContributorsSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var allReferences = false
  @State private var loadState: AsyncLoadState<[Contributor]> = .loading

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Contributors")
          .font(.headline)
        Spacer()
        Picker("History", selection: $allReferences) {
          Text(model.currentBranch?.name ?? "HEAD").tag(false)
          Text("All Branches and Tags").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .layoutPriority(1)
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      Divider()
      AsyncContentView(
        state: loadState,
        isEmpty: \.isEmpty,
        content: list,
        empty: {
          ContentUnavailableView(
            "No Commits Yet", systemImage: "person.2",
            description: Text("Contributors appear once there are commits."))
        },
        errorTitle: "Could Not List Contributors"
      )
    }
    .frame(minWidth: 520, minHeight: 440)
    .task(id: allReferences) {
      loadState = .loading
      do {
        loadState = .loaded(try await model.contributors(allReferences: allReferences))
      } catch {
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  private func list(_ contributors: [Contributor]) -> some View {
    let total = contributors.reduce(0) { $0 + $1.commitCount }
    return VStack(spacing: 0) {
      List(contributors) { contributor in
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 1) {
            Text(contributor.name)
            if !contributor.email.isEmpty {
              Text(contributor.email)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 12)
          Text(contributor.commitCount, format: .number)
            .monospacedDigit()
          Text(
            Double(contributor.commitCount) / Double(max(total, 1)),
            format: .percent.precision(.fractionLength(0))
          )
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 44, alignment: .trailing)
        }
        .contextMenu {
          Button("Copy Name and Email") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(contributor.id, forType: .string)
          }
        }
      }
      Divider()
      Text(
        "\(contributors.count) people, \(total.formatted()) commits. Names and emails follow the repository’s .mailmap."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }
}
