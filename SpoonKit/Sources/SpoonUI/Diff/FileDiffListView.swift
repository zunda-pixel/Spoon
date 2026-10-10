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
  /// Extra per-file actions, offered from the file header's menu.
  var fileActions: ((FileDiff) -> [FileDiffAction])?
  /// Highlight the changed words within modified lines.
  var highlightsWordChanges: Bool

  init(
    diffs: [FileDiff],
    hunkAction: HunkAction? = nil,
    lineSelection: Binding<DiffLineSelection?>? = nil,
    onDiscardHunk: ((FileDiff, Hunk) -> Void)? = nil,
    fileActions: ((FileDiff) -> [FileDiffAction])? = nil,
    highlightsWordChanges: Bool = false
  ) {
    self.highlightsWordChanges = highlightsWordChanges
    self.diffs = diffs
    self.hunkAction = hunkAction
    self.lineSelection = lineSelection
    self.onDiscardHunk = onDiscardHunk
    self.fileActions = fileActions
  }

  /// Files larger than this start with collapsed hunks.
  private static let collapseThreshold = 5_000

  /// Files folded down to their header. Paths outlive reloads of the same
  /// change, so a refresh keeps what the user already set aside.
  @State private var collapsedFileIDs: Set<FileDiff.ID> = []

  var body: some View {
    ScrollViewReader { scrollProxy in
      DiffScrollView {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
          ForEach(diffs) { diff in
            let isExpanded = !collapsedFileIDs.contains(diff.id)
            Section {
              if isExpanded {
                fileBody(diff)
              }
            } header: {
              FileDiffHeaderView(
                diff: diff,
                isExpanded: isExpanded,
                actions: fileActions?(diff) ?? []
              ) { expand, allFiles, headerWasPinned in
                setExpanded(
                  expand, diff, allFiles: allFiles, headerWasPinned: headerWasPinned,
                  scrollProxy: scrollProxy)
              }
            }
          }
        }
        .padding(.bottom, 12)
      }
    }
    .background(.background)
  }

  /// Folds or unfolds `diff`, or every file when `allFiles`.
  private func setExpanded(
    _ isExpanded: Bool, _ diff: FileDiff, allFiles: Bool, headerWasPinned: Bool,
    scrollProxy: ScrollViewProxy
  ) {
    let ids = allFiles ? diffs.map(\.id) : [diff.id]
    if isExpanded {
      collapsedFileIDs.subtract(ids)
    } else {
      collapsedFileIDs.formUnion(ids)
    }
    // Folding the file under a pinned header would leave the viewport deep in
    // later files, and folding every file moves the clicked one; bring its
    // header to the top. Until the fold is laid out the pinned header still
    // counts as visible, so scroll on the next turn.
    if allFiles || (!isExpanded && headerWasPinned) {
      Task { scrollProxy.scrollTo(diff.id, anchor: .topLeading) }
    }
  }

  /// What makes a hunk row current: its file and its exact content.
  private struct HunkIdentity: Hashable {
    let path: String
    let hunkID: Hunk.ID
    let header: String
    let lineCount: Int

    init(diff: FileDiff, hunk: Hunk) {
      path = diff.path
      hunkID = hunk.id
      header = hunk.header
      lineCount = hunk.lines.count
    }
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
          highlightsWordChanges: highlightsWordChanges,
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
        // Hunk IDs are only line numbers, so two files (or two versions of
        // one) share them; LazyVStack then kept showing the previous hunk.
        .id(HunkIdentity(diff: diff, hunk: hunk))
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

/// Observe only the viewport width, keeping resize updates out of the diff owner.
/// A minimum width fills short patches without constraining horizontally scrolling code.
private struct DiffScrollView<Content: View>: View {
  @ViewBuilder var content: Content
  @State private var viewportWidth: CGFloat = 0

  var body: some View {
    ScrollView([.horizontal, .vertical]) {
      content.frame(minWidth: viewportWidth, alignment: .leading)
    }
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      viewportWidth = width
    }
  }
}

@MainActor
struct FileDiffHeaderView: View {
  let diff: FileDiff
  let isExpanded: Bool
  var actions: [FileDiffAction] = []
  /// Folds or unfolds the file, or every file when `allFiles` (Option-click).
  /// `headerWasPinned` reports that the file's top had scrolled above the
  /// viewport, leaving this header pinned over its lines.
  let setExpanded: (_ isExpanded: Bool, _ allFiles: Bool, _ headerWasPinned: Bool) -> Void

  /// At the top of the viewport, where a pinned header sits over its file.
  @State private var isPinned = false

  var body: some View {
    HStack(spacing: 8) {
      Button {
        setExpanded(!isExpanded, NSEvent.modifierFlags.contains(.option), isPinned)
      } label: {
        HStack(spacing: 8) {
          // One rotated symbol keeps the paths aligned between folded and
          // unfolded files; the two chevrons differ in width.
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(
        isExpanded
          ? "Click to collapse; ⌥click collapses all files"
          : "Click to expand; ⌥click expands all files"
      )
      .accessibilityLabel(diff.path)
      .accessibilityValue(accessibilityValue)
      .accessibilityHint("Shows or hides the changes in this file")

      if !actions.isEmpty {
        Menu {
          actionButtons
        } label: {
          Label("File Actions", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Actions for \(diff.path)")
        .accessibilityLabel("Actions for \(diff.path)")
      }
    }
    .contextMenu {
      Button(isExpanded ? "Collapse" : "Expand") {
        setExpanded(!isExpanded, false, isPinned)
      }
      Button("Collapse All") {
        setExpanded(false, true, isPinned)
      }
      Button("Expand All") {
        setExpanded(true, true, isPinned)
      }
      if !actions.isEmpty {
        Divider()
        actionButtons
      }
    }
    .font(.callout.monospacedDigit())
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
    .onGeometryChange(for: Bool.self) { proxy in
      proxy.frame(in: .scrollView).minY <= 0
    } action: { isAtTop in
      isPinned = isAtTop
    }
    .accessibilityElement(children: .contain)
  }

  private var accessibilityValue: String {
    var components = [kindDescription]
    if let oldPath = diff.oldPath {
      components.append("from \(oldPath)")
    }
    components.append("\(diff.additionCount) additions")
    components.append("\(diff.deletionCount) deletions")
    components.append(isExpanded ? "Expanded" : "Collapsed")
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
  let highlightsWordChanges: Bool
  @State private var isExpanded: Bool
  @State private var highlights: HighlightResult?

  private struct HighlightInput: Equatable {
    let hunk: Hunk
    let isEnabled: Bool
  }

  private struct HighlightResult {
    let input: HighlightInput
    let ranges: [Int: [Range<Int>]]
  }

  init(
    diff: FileDiff,
    hunk: Hunk,
    initiallyExpanded: Bool = true,
    highlightsWordChanges: Bool = false,
    action: (title: String, systemImage: String, handler: () -> Void)? = nil,
    lineSelection: Binding<DiffLineSelection?>? = nil,
    onDiscardHunk: (() -> Void)? = nil
  ) {
    self.diff = diff
    self.hunk = hunk
    self.action = action
    self.lineSelection = lineSelection
    self.onDiscardHunk = onDiscardHunk
    self.highlightsWordChanges = highlightsWordChanges
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
        let input = HighlightInput(hunk: hunk, isEnabled: highlightsWordChanges)
        let wordChanges = highlights?.input == input ? highlights?.ranges ?? [:] : [:]
        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { offset, line in
          DiffLineRow(
            line: line,
            changedRanges: wordChanges[offset] ?? [],
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
    // Selecting lines and expanding/collapsing a hunk must not repeat word matching.
    .task(id: HighlightInput(hunk: hunk, isEnabled: highlightsWordChanges)) {
      let changes = highlightsWordChanges ? await Self.highlightRanges(in: hunk) : [:]
      guard !Task.isCancelled else { return }
      highlights = HighlightResult(
        input: HighlightInput(hunk: hunk, isEnabled: highlightsWordChanges), ranges: changes)
    }
  }

  @concurrent
  private static func highlightRanges(in hunk: Hunk) async -> [Int: [Range<Int>]] {
    InlineChanges.ranges(in: hunk)
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
  /// Character ranges of `line.text` that changed against the paired line.
  var changedRanges: [Range<Int>] = []
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
      Text(highlightedText)
        .fixedSize(horizontal: true, vertical: false)
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

  private var highlightedText: AttributedString {
    var text = AttributedString(line.text.isEmpty ? " " : line.text)
    guard !changedRanges.isEmpty else { return text }
    let tint: Color = line.kind == .deletion ? .red : .green
    for range in changedRanges {
      let characters = text.characters
      guard range.upperBound <= characters.count else { continue }
      let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound)
      let upper = characters.index(characters.startIndex, offsetBy: range.upperBound)
      text[lower..<upper].backgroundColor = tint.opacity(0.35)
    }
    return text
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

/// A command offered for one file of a diff, such as restoring its content.
struct FileDiffAction: Identifiable {
  let title: String
  var role: ButtonRole?
  var isEnabled = true
  let perform: () -> Void

  var id: String { title }
}

extension FileDiffHeaderView {
  @ViewBuilder
  fileprivate var actionButtons: some View {
    ForEach(actions) { action in
      Button(action.title, role: action.role, action: action.perform)
        .disabled(!action.isEnabled)
    }
  }
}
