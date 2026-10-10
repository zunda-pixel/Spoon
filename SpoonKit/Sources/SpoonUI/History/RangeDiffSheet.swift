import SpoonCore
import SwiftUI

/// Shows how a branch's commits changed between two versions of it, such as
/// before and after a rebase, using `git range-diff`.
@MainActor
struct RangeDiffSheet: View {
  let model: RepositoryModel
  let branch: Branch
  @Environment(\.dismiss) private var dismiss
  @State private var baseline = BranchVersionBaseline.previousPosition
  @State private var loadState: AsyncLoadState<[RangeDiffEntry]> = .loading

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Text("Compare Versions of “\(branch.name)”")
          .font(.headline)
          .lineLimit(1)
        Spacer()
        Picker("Compare with", selection: $baseline) {
          Text("Previous position").tag(BranchVersionBaseline.previousPosition)
          if let upstream = model.existingRemoteUpstream(of: branch) {
            Text(upstream).tag(BranchVersionBaseline.upstream)
          }
        }
        .layoutPriority(1)
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(12)
      Divider()
      AsyncContentView(
        state: loadState,
        isEmpty: \.isEmpty,
        content: { entryList($0) },
        empty: {
          ContentUnavailableView(
            "No Commits",
            systemImage: "arrow.left.arrow.right",
            description: Text("Neither version has commits of its own.")
          )
        },
        errorTitle: "Could Not Compare Versions"
      )
    }
    .frame(minWidth: 720, minHeight: 460)
    .task(id: baseline) {
      loadState = .loading
      do {
        loadState = .loaded(try await model.compareBranchVersions(branch, with: baseline))
      } catch {
        loadState = .failed(error.localizedDescription)
      }
    }
  }

  private func entryList(_ entries: [RangeDiffEntry]) -> some View {
    List {
      Section {
        ForEach(entries) { entry in
          RangeDiffEntryRow(entry: entry)
        }
      } header: {
        Text(summary(entries))
      }
    }
  }

  private func summary(_ entries: [RangeDiffEntry]) -> String {
    let counts = [
      (entries.count { $0.relation == .unchanged }, "unchanged"),
      (entries.count { $0.relation == .changed }, "changed"),
      (entries.count { $0.relation == .added }, "added"),
      (entries.count { $0.relation == .removed }, "removed"),
    ]
    return counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
  }
}

@MainActor
private struct RangeDiffEntryRow: View {
  let entry: RangeDiffEntry
  /// Changed commits are what the comparison is for, so show them open.
  @State private var isExpanded = true

  var body: some View {
    if entry.relation == .changed, !entry.patchDiff.isEmpty {
      DisclosureGroup(isExpanded: $isExpanded) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(entry.patchDiff.enumerated()), id: \.offset) { _, line in
            Text(line.isEmpty ? " " : line)
              .font(.callout.monospaced())
              .foregroundStyle(color(for: line))
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
        }
        .padding(.vertical, 4)
      } label: {
        summaryRow
      }
    } else {
      summaryRow
    }
  }

  private var summaryRow: some View {
    HStack(spacing: 10) {
      Label(relationTitle, systemImage: relationSymbol)
        .foregroundStyle(relationTint)
        .frame(width: 110, alignment: .leading)
      Text(oids)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)
      Text(entry.subject)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .accessibilityElement(children: .combine)
  }

  private var oids: String {
    let old = entry.oldOID ?? "———"
    let new = entry.newOID ?? "———"
    return "\(old) → \(new)"
  }

  private var relationTitle: String {
    switch entry.relation {
    case .unchanged: "Unchanged"
    case .changed: "Changed"
    case .added: "Added"
    case .removed: "Removed"
    }
  }

  private var relationSymbol: String {
    switch entry.relation {
    case .unchanged: "equal.circle"
    case .changed: "exclamationmark.circle"
    case .added: "plus.circle"
    case .removed: "minus.circle"
    }
  }

  private var relationTint: Color {
    switch entry.relation {
    case .unchanged: .secondary
    case .changed: .orange
    case .added: .green
    case .removed: .red
    }
  }

  /// The outer +/- says how the patch changed between versions.
  private func color(for line: String) -> Color {
    if line.hasPrefix("+") { return .green }
    if line.hasPrefix("-") { return .red }
    if line.hasPrefix("@@") || line.hasPrefix("##") { return .secondary }
    return .primary
  }
}
