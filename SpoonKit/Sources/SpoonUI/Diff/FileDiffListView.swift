import SpoonCore
import SwiftUI

/// Shared renderer for a list of file patches (working-tree diff and
/// commit detail both funnel here).
/// Optional per-hunk action button (Stage Hunk / Unstage Hunk).
@MainActor
struct HunkAction {
  var title: String
  var systemImage: String
  var isEnabled: (FileDiff) -> Bool
  var handler: (FileDiff, Hunk) -> Void
}

@MainActor
struct FileDiffListView: View {
  let diffs: [FileDiff]
  var hunkAction: HunkAction?

  init(diffs: [FileDiff], hunkAction: HunkAction? = nil) {
    self.diffs = diffs
    self.hunkAction = hunkAction
  }

  /// Files larger than this start with collapsed hunks.
  private static let collapseThreshold = 5_000

  var body: some View {
    ScrollView([.vertical]) {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
        ForEach(diffs) { diff in
          Section {
            fileBody(diff)
          } header: {
            FileDiffHeaderView(diff: diff)
          }
        }
      }
      .padding(.bottom, 12)
    }
    .background(.background)
  }

  @ViewBuilder
  private func fileBody(_ diff: FileDiff) -> some View {
    if diff.isBinary {
      Label("Binary file", systemImage: "doc.zipper")
        .foregroundStyle(.secondary)
        .padding(12)
    } else if diff.hunks.isEmpty {
      Label(emptyReason(diff), systemImage: "doc")
        .foregroundStyle(.secondary)
        .padding(12)
    } else {
      let collapsed = diff.lineCount > Self.collapseThreshold
      ForEach(diff.hunks) { hunk in
        HunkView(
          hunk: hunk,
          initiallyExpanded: !collapsed,
          action: hunkAction.flatMap { action in
            action.isEnabled(diff)
              ? (action.title, action.systemImage, { action.handler(diff, hunk) })
              : nil
          }
        )
      }
    }
  }

  private func emptyReason(_ diff: FileDiff) -> String {
    switch diff.kind {
    case .renamed: "Renamed with no content changes"
    case .copied: "Copied with no content changes"
    case .added: "Empty file"
    default: "No textual changes (mode or metadata only)"
    }
  }
}

@MainActor
struct FileDiffHeaderView: View {
  let diff: FileDiff

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
      VStack(alignment: .leading, spacing: 0) {
        Text(diff.path)
          .fontWeight(.medium)
          .lineLimit(1)
          .truncationMode(.middle)
        if let oldPath = diff.oldPath {
          Text("from \(oldPath)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Spacer()
      if diff.additionCount > 0 {
        Text("+\(diff.additionCount)")
          .foregroundStyle(.green)
      }
      if diff.deletionCount > 0 {
        Text("−\(diff.deletionCount)")
          .foregroundStyle(.red)
      }
    }
    .font(.callout.monospacedDigit())
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }

  private var icon: String {
    switch diff.kind {
    case .added: "plus.circle.fill"
    case .deleted: "minus.circle.fill"
    case .renamed, .copied: "arrow.right.circle.fill"
    case .modified: "pencil.circle.fill"
    }
  }

  private var iconColor: Color {
    switch diff.kind {
    case .added: .green
    case .deleted: .red
    case .renamed, .copied: .blue
    case .modified: .yellow
    }
  }
}

@MainActor
struct HunkView: View {
  let hunk: Hunk
  let action: (title: String, systemImage: String, handler: () -> Void)?
  @State private var isExpanded: Bool

  init(
    hunk: Hunk,
    initiallyExpanded: Bool = true,
    action: (title: String, systemImage: String, handler: () -> Void)? = nil
  ) {
    self.hunk = hunk
    self.action = action
    self._isExpanded = State(initialValue: initiallyExpanded)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        Button {
          isExpanded.toggle()
        } label: {
          HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption2)
            Text(hunk.header)
              .lineLimit(1)
          }
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let action {
          Button(action.title, systemImage: action.systemImage) {
            action.handler()
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .labelStyle(.titleAndIcon)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(.quaternary.opacity(0.5))

      if isExpanded {
        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
          DiffLineRow(line: line)
        }
      }
    }
  }
}

@MainActor
struct DiffLineRow: View {
  let line: DiffLine

  private nonisolated static let numberWidth: CGFloat = 40

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      lineNumber(line.oldLine)
      lineNumber(line.newLine)
      Text(marker)
        .frame(width: 16)
      Text(line.text.isEmpty ? " " : line.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(line.kind == .noNewlineMarker ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
    .font(.callout.monospaced())
    .lineLimit(1)
    .padding(.horizontal, 12)
    .background(background)
  }

  private func lineNumber(_ number: Int?) -> some View {
    Text(number.map(String.init) ?? "")
      .frame(width: Self.numberWidth, alignment: .trailing)
      .foregroundStyle(.tertiary)
      .padding(.trailing, 6)
  }

  private var marker: String {
    switch line.kind {
    case .addition: "+"
    case .deletion: "−"
    case .context: ""
    case .noNewlineMarker: ""
    }
  }

  private var background: Color {
    switch line.kind {
    case .addition: .green.opacity(0.12)
    case .deletion: .red.opacity(0.12)
    case .context, .noNewlineMarker: .clear
    }
  }
}
