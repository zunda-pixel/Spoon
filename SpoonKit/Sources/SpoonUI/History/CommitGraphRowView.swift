import SpoonCore
import SwiftUI

@MainActor
struct CommitGraphRowView: View {
  let row: GraphRow
  let referenceLabels: [HistoryReferenceLabel]
  let selectedReference: HistoryReferenceIdentity?

  private nonisolated static let laneWidth: CGFloat = 12
  private nonisolated static let rowHeight: CGFloat = 34
  private nonisolated static let dotRadius: CGFloat = 3.5
  private nonisolated static let palette: [Color] = [
    .blue, .purple, .green, .orange, .pink, .teal, .indigo, .brown,
  ]

  var body: some View {
    HStack(spacing: 10) {
      graphCanvas
        .frame(width: Self.laneWidth * CGFloat(max(row.laneCount, 1)))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          ForEach(referenceLabels.prefix(2)) { referenceLabel in
            referenceBadge(referenceLabel)
          }
          if referenceLabels.count > 2 {
            Text("+\(referenceLabels.count - 2)")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .help(allReferencesHelp)
          }
          if row.commit.isMerge {
            Image(systemName: "arrow.triangle.merge")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Text(row.commit.subject)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        HStack(spacing: 6) {
          Text(row.commit.oid.shortened)
            .font(.caption.monospaced())
          Text(row.commit.authorName)
            .font(.caption)
          Text(row.commit.committedAt, format: .relative(presentation: .named))
            .font(.caption)
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .frame(height: Self.rowHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(row.commit.subject)
    .accessibilityValue(accessibilityValue)
    .accessibilityHint("Select to show commit details; open the context menu for revision actions")
  }

  private var accessibilityValue: String {
    var components = [
      "Commit \(row.commit.oid.shortened)",
      "by \(row.commit.authorName)",
      row.commit.committedAt.formatted(.relative(presentation: .named)),
    ]
    if row.commit.isMerge {
      components.insert("Merge commit", at: 0)
    }
    if !referenceLabels.isEmpty {
      components.append(
        "References: \(referenceLabels.map(accessibilityDescription).joined(separator: ", "))"
      )
    }
    return components.joined(separator: ", ")
  }

  private func referenceBadge(_ referenceLabel: HistoryReferenceLabel) -> some View {
    Label(
      referenceLabel.name,
      systemImage: symbolName(for: referenceLabel.kind)
    )
    .font(.caption2)
    .fontWeight(referenceLabel.isCurrent ? .semibold : nil)
    .lineLimit(1)
    .truncationMode(.middle)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .foregroundStyle(
      isSelected(referenceLabel)
        ? AnyShapeStyle(.tint)
        : referenceLabel.isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    )
    .background(.quaternary, in: Capsule())
    .help(accessibilityDescription(referenceLabel))
    .accessibilityLabel(accessibilityDescription(referenceLabel))
    .accessibilityAddTraits(isSelected(referenceLabel) ? .isSelected : [])
  }

  private func isSelected(_ label: HistoryReferenceLabel) -> Bool {
    label.referenceIdentity != nil && label.referenceIdentity == selectedReference
  }

  private func symbolName(for kind: HistoryReferenceLabel.Kind) -> String {
    switch kind {
    case .localBranch:
      "arrow.trianglehead.branch"
    case .remoteBranch:
      "network"
    case .worktree:
      "folder"
    case .tag:
      "tag"
    case .stash:
      "tray.full"
    }
  }

  private func accessibilityDescription(_ label: HistoryReferenceLabel) -> String {
    let prefix =
      switch label.kind {
      case .localBranch:
        label.isCurrent ? "Current branch" : "Local branch"
      case .remoteBranch:
        "Remote branch"
      case .worktree:
        label.isCurrent ? "Current worktree" : "Worktree"
      case .tag:
        "Tag"
      case .stash:
        "Stash"
      }
    return "\(prefix) \(label.name)\(isSelected(label) ? ", selected focus" : "")"
  }

  private var allReferencesHelp: String {
    referenceLabels.map(accessibilityDescription).joined(separator: "\n")
  }

  private var graphCanvas: some View {
    Canvas { context, size in
      let midY = size.height / 2

      func x(_ lane: Int) -> CGFloat {
        Self.laneWidth * (CGFloat(lane) + 0.5)
      }

      func color(_ lane: Int) -> Color {
        Self.palette[lane % Self.palette.count]
      }

      let dot = CGPoint(x: x(row.lane), y: midY)

      for edge in row.edges {
        var path = Path()
        let laneForColor: Int
        switch edge {
        case .pass(let from, let to):
          path.move(to: CGPoint(x: x(from), y: 0))
          path.addLine(to: CGPoint(x: x(to), y: size.height))
          laneForColor = from
        case .intoCommit(let from):
          path.move(to: CGPoint(x: x(from), y: 0))
          path.addLine(to: dot)
          laneForColor = from
        case .outOfCommit(let to):
          path.move(to: dot)
          path.addLine(to: CGPoint(x: x(to), y: size.height))
          laneForColor = to
        }
        context.stroke(path, with: .color(color(laneForColor)), lineWidth: 1.5)
      }

      let dotRect = CGRect(
        x: dot.x - Self.dotRadius,
        y: dot.y - Self.dotRadius,
        width: Self.dotRadius * 2,
        height: Self.dotRadius * 2
      )
      context.fill(Path(ellipseIn: dotRect), with: .color(color(row.lane)))
    }
  }
}
