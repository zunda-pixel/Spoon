import SpoonCore
import SwiftUI

struct HistoryBranchLabel: Identifiable {
  let name: String
  let isRemote: Bool
  let isCurrent: Bool

  var id: String { "\(isRemote ? "remote" : "local"):\(name)" }
}

@MainActor
struct CommitGraphRowView: View {
  let row: GraphRow
  let branchLabels: [HistoryBranchLabel]

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
          ForEach(branchLabels.prefix(2)) { branchLabel in
            branchBadge(branchLabel)
          }
          if branchLabels.count > 2 {
            Text("+\(branchLabels.count - 2)")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              .help(remainingBranchesHelp)
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
    if !branchLabels.isEmpty {
      components.append(
        "Branches: \(branchLabels.map(\.name).joined(separator: ", "))"
      )
    }
    return components.joined(separator: ", ")
  }

  private func branchBadge(_ branchLabel: HistoryBranchLabel) -> some View {
    Label(
      branchLabel.name,
      systemImage: branchLabel.isRemote ? "network" : "arrow.trianglehead.branch"
    )
    .font(.caption2)
    .lineLimit(1)
    .truncationMode(.middle)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .foregroundStyle(
      branchLabel.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    )
    .background(.quaternary, in: Capsule())
    .help(
      branchLabel.isRemote
        ? "Remote branch \(branchLabel.name)"
        : "\(branchLabel.isCurrent ? "Current branch" : "Local branch") \(branchLabel.name)"
    )
  }

  private var remainingBranchesHelp: String {
    branchLabels.dropFirst(2).map(\.name).joined(separator: ", ")
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
