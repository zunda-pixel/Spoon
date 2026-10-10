import SwiftUI
import Testing

@testable import SpoonUI

@Suite("Wrapping controls")
struct WrappingLayoutTests {
  @MainActor
  @Test func stackedActionsCanWrapAcrossMoreThanTwoRows() {
    let renderer = ImageRenderer(
      content: AdaptiveActionsLayout {
        Color.red.frame(width: 40, height: 20)
        WrappingLayout {
          Color.blue.frame(width: 60, height: 30)
          Color.green.frame(width: 60, height: 30)
          Color.yellow.frame(width: 60, height: 30)
        }
      })
    renderer.proposedSize = ProposedViewSize(width: 100, height: nil)
    #expect(renderer.cgImage?.width == 100)
    #expect(renderer.cgImage?.height == 134)
  }

  @MainActor
  @Test func adaptiveActionsUsesOneRowWhenBothGroupsFit() {
    let renderer = ImageRenderer(
      content: AdaptiveActionsLayout {
        Color.red.frame(width: 60, height: 20)
        Color.blue.frame(width: 60, height: 30)
      })
    renderer.proposedSize = ProposedViewSize(width: 160, height: nil)
    #expect(renderer.cgImage?.width == 160)
    #expect(renderer.cgImage?.height == 30)
  }

  @MainActor
  @Test func adaptiveActionsStacksGroupsWhenTheyDoNotFit() {
    let renderer = ImageRenderer(
      content: AdaptiveActionsLayout {
        Color.red.frame(width: 60, height: 20)
        Color.blue.frame(width: 60, height: 30)
      })
    renderer.proposedSize = ProposedViewSize(width: 100, height: nil)
    #expect(renderer.cgImage?.width == 100)
    #expect(renderer.cgImage?.height == 58)
  }

  @Test func fitsAnExactWidthWithoutWrapping() {
    let arrangement = WrappingLayout.Arrangement(
      sizes: [CGSize(width: 40, height: 20), CGSize(width: 50, height: 30)],
      width: 98, spacing: 8
    )
    #expect(arrangement.size == CGSize(width: 98, height: 30))
    #expect(arrangement.frames[1].origin == CGPoint(x: 48, y: 0))
  }

  @Test func wrapsBelowTheTallestControlAndPreservesOrder() {
    let arrangement = WrappingLayout.Arrangement(
      sizes: [
        CGSize(width: 40, height: 30), CGSize(width: 50, height: 20), CGSize(width: 60, height: 25),
      ],
      width: 98, spacing: 8
    )
    #expect(arrangement.frames[2].origin == CGPoint(x: 0, y: 38))
    #expect(arrangement.size == CGSize(width: 98, height: 63))
  }

  @Test func unconstrainedWidthUsesOneRow() {
    let arrangement = WrappingLayout.Arrangement(
      sizes: [CGSize(width: 40, height: 20), CGSize(width: 50, height: 30)],
      width: nil, spacing: 8
    )
    #expect(arrangement.size == CGSize(width: 98, height: 30))
  }

  @Test func emptyContentHasNoSpacingOrHeight() {
    let arrangement = WrappingLayout.Arrangement(sizes: [], width: 100, spacing: 8)
    #expect(arrangement.frames.isEmpty)
    #expect(arrangement.size == .zero)
  }

  @Test func zeroWidthDoesNotAddAnEmptyFirstRow() {
    let arrangement = WrappingLayout.Arrangement(
      sizes: [CGSize(width: 40, height: 20), CGSize(width: 50, height: 30)],
      width: 0, spacing: 8
    )
    #expect(arrangement.frames[0].origin == .zero)
    #expect(arrangement.frames[1].origin == CGPoint(x: 0, y: 28))
    #expect(arrangement.size == CGSize(width: 50, height: 58))
  }
}
