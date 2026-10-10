import SwiftUI

/// Measures controls at their ideal size, then wraps instead of truncating labels.
/// Layout owns measurement and placement; no geometry is copied into view state.
struct WrappingLayout: Layout {
  var spacing: CGFloat = 8

  struct Cache {
    var idealSizes: [CGSize]
  }

  func makeCache(subviews: Subviews) -> Cache {
    Cache(idealSizes: subviews.map { $0.sizeThatFits(.unspecified) })
  }

  func updateCache(_ cache: inout Cache, subviews: Subviews) {
    cache = makeCache(subviews: subviews)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    arrangement(width: proposal.width, subviews: subviews, cache: cache).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
  ) {
    let arrangement = arrangement(width: bounds.width, subviews: subviews, cache: cache)
    for (index, subview) in subviews.enumerated() {
      let frame = arrangement.frames[index]
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(frame.size)
      )
    }
  }

  private func arrangement(width: CGFloat?, subviews: Subviews, cache: Cache) -> Arrangement {
    let limit = width.flatMap { $0.isFinite ? max(0, $0) : nil }
    let sizes = subviews.enumerated().map { index, subview in
      let ideal = cache.idealSizes[index]
      if let limit, ideal.width > limit {
        return subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
      }
      return ideal
    }
    return Arrangement(sizes: sizes, width: limit, spacing: spacing)
  }

  /// Pure placement calculation, shared by measurement and placement.
  struct Arrangement {
    let frames: [CGRect]
    let size: CGSize

    init(sizes: [CGSize], width: CGFloat?, spacing: CGFloat) {
      let limit = width ?? .infinity
      var frames: [CGRect] = []
      var x: CGFloat = 0
      var y: CGFloat = 0
      var rowHeight: CGFloat = 0
      var usedWidth: CGFloat = 0
      for size in sizes {
        if x > 0, x + size.width > limit {
          x = 0
          y += rowHeight + spacing
          rowHeight = 0
        }
        frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
        usedWidth = max(usedWidth, x + size.width)
        rowHeight = max(rowHeight, size.height)
        x += size.width + spacing
      }
      self.frames = frames
      self.size = CGSize(width: usedWidth, height: y + rowHeight)
    }
  }
}

/// A message/options group and an actions group share a row when both fit.
/// Keeps one subtree alive while resizing, including menus and focused controls.
struct AdaptiveActionsLayout: Layout {
  var spacing: CGFloat = 12
  var rowSpacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard subviews.count == 2 else { return .zero }
    let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
    let width =
      proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
      ?? (ideal[0].width + spacing + ideal[1].width)
    if ideal[0].width + spacing + ideal[1].width <= width {
      return CGSize(width: width, height: max(ideal[0].height, ideal[1].height))
    }
    let sizes = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
    return CGSize(width: width, height: sizes[0].height + rowSpacing + sizes[1].height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 2 else { return }
    let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
    let fits = ideal[0].width + spacing + ideal[1].width <= bounds.width
    let leadingProposal = ProposedViewSize(width: fits ? ideal[0].width : bounds.width, height: nil)
    let leadingSize = subviews[0].sizeThatFits(leadingProposal)
    subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: leadingProposal)
    let actionsWidth = fits ? bounds.width - leadingSize.width - spacing : bounds.width
    let actionsProposal = ProposedViewSize(width: actionsWidth, height: nil)
    let actionsSize = subviews[1].sizeThatFits(actionsProposal)
    subviews[1].place(
      at: CGPoint(
        x: bounds.maxX - actionsSize.width,
        y: fits ? bounds.minY : bounds.minY + leadingSize.height + rowSpacing
      ),
      anchor: .topLeading,
      proposal: actionsProposal
    )
  }
}
