import SpoonCore
import SwiftUI

/// Shown while `git bisect` runs: progress and the good / bad / skip marks
/// for the checked-out commit.
@MainActor
struct BisectBannerView: View {
  let model: RepositoryModel
  let state: BisectState
  let navigation: RepositoryNavigationState
  @State private var confirmingReset = false

  var body: some View {
    AdaptiveActionsLayout {
      message
      WrappingLayout { actions }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.blue.opacity(0.1), ignoresSafeAreaEdges: [])
    .overlay(alignment: .bottom) {
      Divider()
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Bisect status")
    .confirmationDialog("End bisect?", isPresented: $confirmingReset) {
      Button("End Bisect", role: .destructive) {
        Task { await model.resetBisect() }
      }
    } message: {
      Text("The marks are discarded and the commit checked out before the bisect is restored.")
    }
  }

  private var found: ObjectID? { model.bisectResult }

  private var message: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: found == nil ? "scope" : "checkmark.circle.fill")
        .foregroundStyle(.blue)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder
  private var actions: some View {
    if found == nil {
      ForEach([BisectMark.good, .bad, .skip], id: \.self) { mark in
        Button(markTitle(mark)) {
          Task { await model.markBisect(mark) }
        }
        .disabled(model.isBusy || state.badOID == nil && mark != .bad)
        .help(markHelp(mark))
      }
      Button("Run…") { navigation.present(.bisectRun) }
        .disabled(model.isBusy || state.badOID == nil || state.goodOIDs.isEmpty)
        .help("Let a command, such as a test, mark each commit until the first bad one is found")
    }
    Button(found == nil ? "End Bisect…" : "End Bisect") {
      if found == nil {
        confirmingReset = true
      } else {
        Task {
          await model.resetBisect()
          model.dismissBisectResult()
        }
      }
    }
    .disabled(model.isBusy)
  }

  private var title: String {
    if let found {
      return "First bad commit: \(found.shortened)"
    }
    guard let remaining = state.remainingCount else { return "Bisecting" }
    let steps =
      state.estimatedStepsLeft.map { " (roughly \($0) \($0 == 1 ? "step" : "steps"))" } ?? ""
    return "Bisecting — \(remaining) \(remaining == 1 ? "commit" : "commits") left\(steps)"
  }

  private var subtitle: String {
    if found != nil {
      return "End the bisect to return to the commit you started from."
    }
    let testing = model.status?.headOID.map { " \($0.shortened)" } ?? ""
    return "Test the checked-out commit\(testing), then mark it good or bad."
  }

  private func markTitle(_ mark: BisectMark) -> String {
    switch mark {
    case .good: "Good"
    case .bad: "Bad"
    case .skip: "Skip"
    }
  }

  private func markHelp(_ mark: BisectMark) -> String {
    switch mark {
    case .good: "The problem does not occur in this commit"
    case .bad: "The problem occurs in this commit"
    case .skip: "This commit cannot be tested; choose another one nearby"
    }
  }
}
