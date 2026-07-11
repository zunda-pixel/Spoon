/// One drawable segment inside a history row. Rows are one commit tall;
/// history flows downward (newest first), so "top" is toward newer commits.
public enum GraphEdge: Sendable, Hashable {
  /// A lane passing straight through the row without touching the dot.
  case pass(from: Int, to: Int)
  /// A lane from the top boundary converging into this row's commit dot.
  case intoCommit(from: Int)
  /// A lane leaving this row's commit dot toward the bottom boundary.
  case outOfCommit(to: Int)
}

public struct GraphRow: Sendable, Hashable, Identifiable {
  public var commit: Commit
  /// Column of this commit's dot.
  public var lane: Int
  /// Total columns needed to draw this row.
  public var laneCount: Int
  public var edges: [GraphEdge]

  public var id: String { commit.id }
}

/// Pure lane assignment for a topologically ordered commit list
/// (`git log --topo-order`, newest first).
public enum CommitGraphLayout {
  public static func assignLanes(_ commits: [Commit]) -> [GraphRow] {
    // Each slot holds the commit a lane is waiting for (its next parent
    // down the page), or nil for a free column.
    var lanes: [ObjectID?] = []
    var rows: [GraphRow] = []
    rows.reserveCapacity(commits.count)

    for commit in commits {
      let top = lanes
      var edges: [GraphEdge] = []

      // Lanes whose awaited commit is this one converge into the dot.
      let waiting = lanes.indices.filter { lanes[$0] == commit.oid }
      let lane: Int
      if let first = waiting.first {
        lane = first
      } else if let free = lanes.firstIndex(where: { $0 == nil }) {
        lane = free  // new tip in a recycled column
      } else {
        lanes.append(nil)
        lane = lanes.count - 1  // new tip in a fresh column
      }

      for index in waiting {
        edges.append(.intoCommit(from: index))
        lanes[index] = nil
      }

      // Route parents out of the dot: first parent keeps the commit's lane,
      // merge parents join an existing lane or claim a free one.
      var parentLanes: Set<Int> = []
      for (index, parent) in commit.parents.enumerated() {
        if index == 0 {
          lanes[lane] = parent
          parentLanes.insert(lane)
        } else if let existing = lanes.firstIndex(of: parent) {
          parentLanes.insert(existing)
        } else if let free = lanes.firstIndex(where: { $0 == nil }) {
          lanes[free] = parent
          parentLanes.insert(free)
        } else {
          lanes.append(parent)
          parentLanes.insert(lanes.count - 1)
        }
      }
      for parentLane in parentLanes.sorted() {
        edges.append(.outOfCommit(to: parentLane))
      }

      // Unrelated active lanes continue straight through.
      for index in top.indices where top[index] != nil && top[index] != commit.oid {
        edges.append(.pass(from: index, to: index))
      }

      rows.append(
        GraphRow(
          commit: commit,
          lane: lane,
          laneCount: max(top.count, lanes.count, lane + 1),
          edges: edges
        )
      )

      while let last = lanes.last, last == nil {
        lanes.removeLast()
      }
    }
    return rows
  }
}
