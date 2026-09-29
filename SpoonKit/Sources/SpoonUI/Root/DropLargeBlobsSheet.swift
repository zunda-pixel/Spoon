import SpoonCore
import SwiftUI

/// Reclaims disk space in a partial clone with `git repack --drop-filtered`.
@MainActor
struct DropLargeBlobsSheet: View {
  let model: RepositoryModel
  @Environment(\.dismiss) private var dismiss
  @State private var megabytes = 10

  private static let thresholds = [1, 10, 50, 100, 500]

  var body: some View {
    SheetFormLayout(title: "Remove Large Downloaded Blobs") {
      Picker("Remove files larger than", selection: $megabytes) {
        ForEach(Self.thresholds, id: \.self) { value in
          Text("\(value) MB").tag(value)
        }
      }
      .frame(width: 400)
      Text(
        "Git deletes local copies of larger file versions and downloads them again from “\(model.partialCloneRemote ?? "the promisor remote")” when they are needed. Files used by the current index are kept. This can take a while on large repositories."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(width: 400, alignment: .leading)
    } actions: {
      Button("Cancel", role: .cancel) { dismiss() }
      Button("Remove Blobs", role: .destructive) {
        let byteLimit = megabytes * 1024 * 1024
        dismiss()
        Task { await model.dropLargeBlobs(largerThan: byteLimit) }
      }
      .keyboardShortcut(.defaultAction)
      .disabled(model.isBusy || model.isSequencing)
    }
  }
}
