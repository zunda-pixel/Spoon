import SpoonCore
import SwiftUI

/// Window-wide banner shown while a rebase / cherry-pick / revert is paused
/// (conflict or edit stop), offering Continue / Skip / Abort.
@MainActor
struct SequencerBannerView: View {
  let model: RepositoryModel
  let state: SequencerState
  @State private var confirmingAbort = false

  private var hasConflicts: Bool {
    !(model.status?.conflictedEntries.isEmpty ?? true)
  }

  var body: some View {
    // The banner lives in the content column, which can be narrow: fall back
    // to stacking the actions under the message instead of squeezing it.
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        message
        Spacer(minLength: 0)
        actions
      }
      VStack(alignment: .leading, spacing: 8) {
        message
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          actions
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    // Keep the tint out of the toolbar area above the column.
    .background(.yellow.opacity(0.12), ignoresSafeAreaEdges: [])
    .overlay(alignment: .bottom) {
      Divider()
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(kindName) status")
    .accessibilityValue(hasConflicts ? "Paused with conflicts" : "Paused")
    .confirmationDialog("Abort \(kindName)?", isPresented: $confirmingAbort) {
      Button("Abort \(kindName)", role: .destructive) {
        Task { await model.abortSequencer() }
      }
    } message: {
      Text("All progress from this operation will be discarded and the branch restored.")
    }
  }

  private var message: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .accessibilitySortPriority(2)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilitySortPriority(1)
      }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder
  private var actions: some View {
    Button("Continue") {
      Task { await model.continueSequencer() }
    }
    .disabled(hasConflicts || model.isBusy)
    .help(hasConflicts ? "Resolve and stage all conflicts first" : "Resume the operation")
    .accessibilityHint(
      hasConflicts ? "Resolve and stage all conflicts first" : "Resumes the paused operation"
    )
    if state.kind != .merge {
      // `git merge` has no --skip.
      Button("Skip") {
        Task { await model.skipSequencer() }
      }
      .disabled(model.isBusy)
      .help("Skip the current commit and resume")
    }
    Button("Abort…", role: .destructive) {
      confirmingAbort = true
    }
    .disabled(model.isBusy)
  }

  private var kindName: String {
    switch state.kind {
    case .rebase: "Rebase"
    case .cherryPick: "Cherry-Pick"
    case .revert: "Revert"
    case .merge: "Merge"
    case .applyingPatches: "Patch Application"
    }
  }

  private var title: String {
    switch state.kind {
    case .rebase:
      var text = "Rebasing"
      if let branch = state.branchName {
        text += " \(branch)"
      }
      if let step = state.stepNumber, let count = state.stepCount {
        text += " — step \(step) of \(count)"
      }
      return text
    case .cherryPick:
      return "Cherry-pick in progress"
    case .revert:
      return "Revert in progress"
    case .merge:
      return "Merge in progress"
    case .applyingPatches:
      var text = "Applying patches"
      if let step = state.stepNumber, let count = state.stepCount {
        text += " — \(step) of \(count)"
      }
      return text
    }
  }

  private var subtitle: String {
    if hasConflicts {
      return "Resolve conflicts in Changes, stage the files, then Continue."
    }
    if state.kind == .rebase, let stopped = state.stoppedOID {
      return "Paused for edit at \(stopped.shortened) — amend in Changes, then Continue."
    }
    return "Continue when ready, or Abort to restore the previous state."
  }
}
