import SpoonCore
import SwiftUI

/// Diff display toggles shown above a diff; the View menu has the same ones.
@MainActor
struct DiffOptionsBar: View {
  @Bindable var model: RepositoryModel

  var body: some View {
    HStack(spacing: 14) {
      if model.diffIgnoresWhitespace {
        Label("Whitespace changes hidden", systemImage: "eye.slash")
          .foregroundStyle(.secondary)
          .help("Turn off Ignore Whitespace to stage or discard hunks and lines")
      }
      Spacer()
      Toggle("Ignore Whitespace", isOn: $model.diffIgnoresWhitespace)
        .help("Hide changes that only add, remove, or alter whitespace")
      Toggle("Highlight Changed Words", isOn: $model.diffHighlightsWordChanges)
        .help("Mark the words that changed within modified lines")
    }
    .toggleStyle(.checkbox)
    .controlSize(.small)
    .font(.caption)
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
  }
}
