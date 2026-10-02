import SpoonCore
import SwiftUI

@MainActor
struct HistoryReferenceFilterButtons: View {
  let model: RepositoryModel
  let referenceID: String
  @Environment(\.backgroundProminence) private var backgroundProminence

  var body: some View {
    HStack(spacing: 2) {
      Button {
        Task { await model.toggleHistoryFocus(referenceID) }
      } label: {
        Image(systemName: model.isHistoryReferenceFocused(referenceID) ? "eye.fill" : "eye")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(
        style(isOn: model.isHistoryReferenceFocused(referenceID))
      )
      .help(model.isHistoryReferenceFocused(referenceID) ? "Stop showing only this reference" : "Show only this reference")
      .accessibilityLabel(model.isHistoryReferenceFocused(referenceID) ? "Stop showing only this reference" : "Show only this reference")

      Button {
        Task { await model.toggleHistoryHidden(referenceID) }
      } label: {
        Image(systemName: model.isHistoryReferenceHidden(referenceID) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(
        style(isOn: model.isHistoryReferenceHidden(referenceID))
      )
      .help(model.isHistoryReferenceHidden(referenceID) ? "Show this reference in history" : "Hide this reference from history")
      .accessibilityLabel(model.isHistoryReferenceHidden(referenceID) ? "Show this reference in history" : "Hide this reference from history")
    }
    .font(.caption)
    .fixedSize()
  }

  /// On a selected row the accent color is the highlight itself, so an
  /// active button switches to the primary color there.
  private func style(isOn: Bool) -> AnyShapeStyle {
    guard isOn else { return AnyShapeStyle(.secondary) }
    return backgroundProminence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint)
  }
}
