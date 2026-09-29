import SpoonCore
import SwiftUI

/// Confirms `git backfill`, showing how much it would download when git can
/// measure that without fetching.
@MainActor
struct BackfillSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var estimate: BackfillEstimate?
  @State private var estimateErrorMessage: String?

  var body: some View {
    SheetFormLayout(title: "Backfill Missing Objects") {
      Group {
        Text(
          "Downloads the file versions this partial clone skipped, in batches, so history and diffs no longer fetch them one at a time."
        )
        if model.canEstimateBackfill {
          estimateView
        }
      }
      .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Backfill") {
        dismiss()
        Task { await model.backfill() }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(model.isBusy || model.isSequencing || estimate?.missingObjectCount == 0)
    }
    .task {
      guard model.canEstimateBackfill else { return }
      do {
        estimate = try await model.backfillEstimate()
      } catch {
        estimateErrorMessage = error.localizedDescription
      }
    }
  }

  @ViewBuilder
  private var estimateView: some View {
    if let estimateErrorMessage {
      Label(estimateErrorMessage, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.secondary)
    } else if let estimate {
      if estimate.missingObjectCount == 0 {
        Label(
          "Every object reachable from HEAD is already downloaded.",
          systemImage: "checkmark.circle"
        )
      } else {
        LabeledContent("Missing objects", value: estimate.missingObjectCount.formatted())
        if let bytes = estimate.downloadByteCount {
          LabeledContent(
            "Download size",
            value: "About " + Int64(bytes).formatted(.byteCount(style: .file))
          )
        } else if let reason = estimate.sizeUnavailableReason {
          Text(reason)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } else {
      ProgressView("Measuring missing objects…")
        .frame(maxWidth: .infinity)
    }
  }
}
