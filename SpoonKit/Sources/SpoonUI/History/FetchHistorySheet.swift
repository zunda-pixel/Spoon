import SpoonCore
import SwiftUI

/// Fetches older history into a shallow clone: a number of commits, back
/// to a date, or all of it.
@MainActor
struct FetchHistorySheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var choice = Choice.commits
  @State private var commitCount = 100
  @State private var since = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now

  private enum Choice: Hashable {
    case commits, since, full
  }

  var body: some View {
    SheetFormLayout(
      title: "Fetch More History",
      subtitle: "This is a shallow clone, so commits older than its boundary aren’t downloaded."
    ) {
      Picker("Fetch", selection: $choice) {
        HStack {
          Text("The")
          TextField("Commits", value: $commitCount, format: .number)
            .frame(width: 70)
            .disabled(choice != .commits)
          Text("commits before the current boundary")
        }
        .tag(Choice.commits)
        HStack {
          Text("Every commit since")
          DatePicker("Since", selection: $since, displayedComponents: .date)
            .labelsHidden()
            .disabled(choice != .since)
        }
        .tag(Choice.since)
        Text("The full history (ends the shallow clone)")
          .tag(Choice.full)
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Fetch", action: fetch)
        .keyboardShortcut(.defaultAction)
        .disabled(choice == .commits && commitCount < 1)
    }
    .frame(width: 460)
  }

  private func fetch() {
    let depth: HistoryDepth =
      switch choice {
      case .commits: .commits(commitCount)
      case .since: .since(since)
      case .full: .full
      }
    dismiss()
    Task { await model.deepenHistory(depth) }
  }
}

/// Above History in a shallow clone, where older commits are missing.
@MainActor
struct ShallowHistoryBanner: View {
  let model: RepositoryModel
  let navigation: RepositoryNavigationState

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "clock.badge.questionmark")
        .foregroundStyle(.secondary)
      ViewThatFits(in: .horizontal) {
        Text("Shallow clone: older history isn’t downloaded.")
        Text("Shallow clone")
      }
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .help("Commits older than this clone’s boundary aren’t downloaded.")
      Spacer(minLength: 8)
      Button("Fetch More…") { navigation.present(.fetchHistory) }
        .disabled(model.isBusy)
    }
    .font(.callout)
    .controlSize(.small)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .overlay(alignment: .bottom) { Divider() }
  }
}
