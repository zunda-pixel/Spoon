import AppKit
import SpoonCore
import SwiftUI

/// Optional per-hunk action button (Stage Hunk / Unstage Hunk).
@MainActor
struct HunkAction {
  var title: String
  var systemImage: String
  var isEnabled: (FileDiff) -> Bool
  var handler: (FileDiff, Hunk) -> Void
}

/// One contiguous line selection inside a single hunk, for line-level
/// discard. Offsets index into `hunk.lines`.
struct DiffLineSelection: Equatable {
  var fileID: String
  var hunkID: Hunk.ID
  var offsets: Set<Int>
  var anchor: Int?
}

/// Shared renderer for a list of file patches (working-tree diff and
/// commit detail both funnel here). Line selection and discard affordances
/// activate only when the owner passes the bindings (unstaged diffs).
@MainActor
struct FileDiffListView: View {
  let diffs: [FileDiff]
  var hunkAction: HunkAction?
  var lineSelection: Binding<DiffLineSelection?>?
  var onDiscardHunk: ((FileDiff, Hunk) -> Void)?

  init(
    diffs: [FileDiff],
    hunkAction: HunkAction? = nil,
    lineSelection: Binding<DiffLineSelection?>? = nil,
    onDiscardHunk: ((FileDiff, Hunk) -> Void)? = nil
  ) {
    self.diffs = diffs
    self.hunkAction = hunkAction
    self.lineSelection = lineSelection
    self.onDiscardHunk = onDiscardHunk
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
          diff: diff,
          hunk: hunk,
          initiallyExpanded: !collapsed,
          action: hunkAction.flatMap { action in
            action.isEnabled(diff)
              ? (action.title, action.systemImage, { action.handler(diff, hunk) })
              : nil
          },
          lineSelection: linesSelectable(diff, hunk) ? lineSelection : nil,
          onDiscardHunk: linesSelectable(diff, hunk)
            ? onDiscardHunk.map { handler in { handler(diff, hunk) } }
            : nil
        )
      }
    }
  }

  /// Line-level discard is only well-defined for content edits to tracked
  /// text files, and end-of-file newline changes are excluded (see
  /// DiffPatchBuilder.discardPatch).
  private func linesSelectable(_ diff: FileDiff, _ hunk: Hunk) -> Bool {
    lineSelection != nil
      && diff.kind == .modified
      && !diff.isBinary
      && !hunk.lines.contains { $0.kind == .noNewlineMarker }
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(diff.path)
    .accessibilityValue(accessibilityValue)
  }

  private var accessibilityValue: String {
    var components = [kindDescription]
    if let oldPath = diff.oldPath {
      components.append("from \(oldPath)")
    }
    components.append("\(diff.additionCount) additions")
    components.append("\(diff.deletionCount) deletions")
    return components.joined(separator: ", ")
  }

  private var kindDescription: String {
    switch diff.kind {
    case .added: "Added file"
    case .deleted: "Deleted file"
    case .renamed: "Renamed file"
    case .copied: "Copied file"
    case .modified: "Modified file"
    }
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
  let diff: FileDiff
  let hunk: Hunk
  let action: (title: String, systemImage: String, handler: () -> Void)?
  let lineSelection: Binding<DiffLineSelection?>?
  let onDiscardHunk: (() -> Void)?
  @State private var isExpanded: Bool

  init(
    diff: FileDiff,
    hunk: Hunk,
    initiallyExpanded: Bool = true,
    action: (title: String, systemImage: String, handler: () -> Void)? = nil,
    lineSelection: Binding<DiffLineSelection?>? = nil,
    onDiscardHunk: (() -> Void)? = nil
  ) {
    self.diff = diff
    self.hunk = hunk
    self.action = action
    self.lineSelection = lineSelection
    self.onDiscardHunk = onDiscardHunk
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
        .accessibilityLabel(hunk.header)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides the lines in this hunk")

        if let action {
          Button(action.title, systemImage: action.systemImage) {
            action.handler()
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .labelStyle(.titleAndIcon)
        }

        if let onDiscardHunk {
          Button("Discard Hunk…", systemImage: "arrow.uturn.backward", role: .destructive) {
            onDiscardHunk()
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
          .labelStyle(.titleAndIcon)
          .foregroundStyle(.red)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 4)
      .background(.quaternary.opacity(0.5))

      if isExpanded {
        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { offset, line in
          DiffLineRow(
            line: line,
            isSelectable: lineSelection != nil && line.kind != .context,
            isSelected: isSelected(offset),
            onSelect: lineSelection != nil && line.kind != .context
              ? { handleTap(offset) }
              : nil
          )
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Diff hunk")
  }

  private var selectionKey: (String, Hunk.ID) { (diff.id, hunk.id) }

  private func isSelected(_ offset: Int) -> Bool {
    guard let selection = lineSelection?.wrappedValue else { return false }
    return selection.fileID == diff.id && selection.hunkID == hunk.id
      && selection.offsets.contains(offset)
  }

  /// Click = select one line; shift-click = extend the range from the
  /// anchor (changed lines only); ⌘-click = toggle individual lines.
  private func handleTap(_ offset: Int) {
    guard let binding = lineSelection else { return }
    let modifiers = NSEvent.modifierFlags
    let current = binding.wrappedValue
    let sameHunk = current?.fileID == diff.id && current?.hunkID == hunk.id

    if modifiers.contains(.shift), sameHunk, let anchor = current?.anchor {
      let range = min(anchor, offset)...max(anchor, offset)
      let offsets = Set(
        range.filter {
          hunk.lines[$0].kind == .addition || hunk.lines[$0].kind == .deletion
        }
      )
      binding.wrappedValue = DiffLineSelection(
        fileID: diff.id, hunkID: hunk.id, offsets: offsets, anchor: anchor)
    } else if modifiers.contains(.command), sameHunk, var selection = current {
      selection.offsets.formSymmetricDifference([offset])
      binding.wrappedValue = selection.offsets.isEmpty ? nil : selection
    } else if sameHunk, current?.offsets == [offset] {
      binding.wrappedValue = nil  // clicking the only selected line deselects
    } else {
      binding.wrappedValue = DiffLineSelection(
        fileID: diff.id, hunkID: hunk.id, offsets: [offset], anchor: offset)
    }
  }
}

@MainActor
struct DiffLineRow: View {
  let line: DiffLine
  var isSelectable = false
  var isSelected = false
  var onSelect: (() -> Void)?

  private nonisolated static let numberWidth: CGFloat = 40

  @ViewBuilder
  var body: some View {
    if isSelectable, let onSelect {
      Button(action: onSelect) {
        content
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .accessibilityHint(
        "Select this changed line; Shift extends and Command toggles the selection")
    } else {
      content
    }
  }

  private var content: some View {
    HStack(alignment: .top, spacing: 0) {
      lineNumber(line.oldLine)
      lineNumber(line.newLine)
      Text(marker)
        .frame(width: 16)
      Text(line.text.isEmpty ? " " : line.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(
          line.kind == .noNewlineMarker ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
    .font(.callout.monospaced())
    .lineLimit(1)
    .padding(.horizontal, 12)
    .background(isSelected ? Color.accentColor.opacity(0.28) : background)
    .contentShape(Rectangle())
    .help(isSelectable ? "Click to select; ⇧click extends, ⌘click toggles" : "")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(isSelected ? "Selected" : "")
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

  private var accessibilityLabel: String {
    let location: String
    switch (line.oldLine, line.newLine) {
    case (let old?, let new?): location = "Old line \(old), new line \(new)"
    case (let old?, nil): location = "Old line \(old)"
    case (nil, let new?): location = "New line \(new)"
    case (nil, nil): location = "Diff marker"
    }
    return "\(kindDescription), \(location), \(line.text)"
  }

  private var kindDescription: String {
    switch line.kind {
    case .addition: "Addition"
    case .deletion: "Deletion"
    case .context: "Context"
    case .noNewlineMarker: "No newline at end of file"
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
