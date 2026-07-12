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
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Continue") {
        Task { await model.continueSequencer() }
      }
      .disabled(hasConflicts || model.isBusy)
      .help(hasConflicts ? "Resolve and stage all conflicts first" : "Resume the operation")
      Button("Skip") {
        Task { await model.skipSequencer() }
      }
      .disabled(model.isBusy)
      .help("Skip the current commit and resume")
      Button("Abort…", role: .destructive) {
        confirmingAbort = true
      }
      .disabled(model.isBusy)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.yellow.opacity(0.12))
    .overlay(alignment: .bottom) {
      Divider()
    }
    .confirmationDialog("Abort \(kindName)?", isPresented: $confirmingAbort) {
      Button("Abort \(kindName)", role: .destructive) {
        Task { await model.abortSequencer() }
      }
    } message: {
      Text("All progress from this operation will be discarded and the branch restored.")
    }
  }

  private var kindName: String {
    switch state.kind {
    case .rebase: "Rebase"
    case .cherryPick: "Cherry-Pick"
    case .revert: "Revert"
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
