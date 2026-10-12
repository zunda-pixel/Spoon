import AppKit
import SpoonCore
import SwiftUI

/// Font and row height shared by the diff gutter and the selectable code
/// text, so each line's number, marker, and background line up with it.
@MainActor
enum DiffTextMetrics {
  static let font = NSFont.monospacedSystemFont(
    ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize,
    weight: .regular
  )
  static let rowHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: font))
}

/// A hunk's code as one read-only text view, so a range can be selected
/// across lines, character by character, and copied with ⌘C. Line numbers
/// and +/− markers live outside it, so they are never copied.
struct DiffCodeText: NSViewRepresentable {
  let lines: [DiffLine]
  /// Changed character ranges per line offset, highlighted like before.
  let changedRanges: [Int: [Range<Int>]]

  func makeNSView(context: Context) -> DiffCodeTextView {
    DiffCodeTextView()
  }

  func updateNSView(_ view: DiffCodeTextView, context: Context) {
    view.show(DiffCodeTextView.Content(lines: lines, changedRanges: changedRanges))
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: DiffCodeTextView, context: Context
  ) -> CGSize? {
    nsView.contentSize
  }
}

final class DiffCodeTextView: NSTextView {
  struct Content: Equatable {
    let lines: [DiffLine]
    let changedRanges: [Int: [Range<Int>]]
  }

  private var content: Content?
  // NSTextView only keeps unowned references to its TextKit objects.
  private let storage = NSTextStorage()
  private let codeLayoutManager = NSLayoutManager()
  private let container: NSTextContainer

  init() {
    storage.addLayoutManager(codeLayoutManager)
    // Lines never wrap: the diff scrolls horizontally instead.
    container = NSTextContainer(
      size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    container.widthTracksTextView = false
    container.heightTracksTextView = false
    container.lineFragmentPadding = 0
    codeLayoutManager.addTextContainer(container)
    super.init(frame: .zero, textContainer: container)
    isEditable = false
    isSelectable = true
    isRichText = false
    drawsBackground = false
    textContainerInset = .zero
    isHorizontallyResizable = false
    isVerticallyResizable = false
    setAccessibilityLabel("Diff code")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Replaces the text only when it changed, so redrawing the hunk (for
  /// example when a line is selected in the gutter) keeps the selection.
  func show(_ newContent: Content) {
    guard newContent != content else { return }
    content = newContent
    storage.setAttributedString(Self.attributedString(for: newContent))
    setSelectedRange(NSRange(location: 0, length: 0))
    invalidateIntrinsicContentSize()
  }

  /// One row per line at the gutter's row height; as wide as the longest line.
  var contentSize: CGSize {
    guard let content else { return .zero }
    codeLayoutManager.ensureLayout(for: container)
    let used = codeLayoutManager.usedRect(for: container)
    return CGSize(
      width: max(ceil(used.width), 1),
      height: DiffTextMetrics.rowHeight * CGFloat(content.lines.count)
    )
  }

  private static func attributedString(for content: Content) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = DiffTextMetrics.rowHeight
    paragraph.maximumLineHeight = DiffTextMetrics.rowHeight
    paragraph.lineBreakMode = .byClipping

    let result = NSMutableAttributedString()
    for (offset, line) in content.lines.enumerated() {
      if offset > 0 {
        result.append(NSAttributedString(string: "\n"))
      }
      let attributed = NSMutableAttributedString(
        string: line.text,
        attributes: [
          .foregroundColor: line.kind == .noNewlineMarker
            ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
      )
      let tint: NSColor = line.kind == .deletion ? .systemRed : .systemGreen
      for range in content.changedRanges[offset] ?? [] {
        guard let nsRange = nsRange(of: range, in: line.text) else { continue }
        attributed.addAttribute(
          .backgroundColor, value: tint.withAlphaComponent(0.35), range: nsRange)
      }
      result.append(attributed)
    }
    result.addAttributes(
      [.font: DiffTextMetrics.font, .paragraphStyle: paragraph],
      range: NSRange(location: 0, length: result.length)
    )
    return result
  }

  /// Converts a range of Characters (as `InlineChanges` reports) to UTF-16.
  private static func nsRange(of range: Range<Int>, in text: String) -> NSRange? {
    guard range.lowerBound >= 0, range.upperBound <= text.count else { return nil }
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    return NSRange(lower..<upper, in: text)
  }
}
