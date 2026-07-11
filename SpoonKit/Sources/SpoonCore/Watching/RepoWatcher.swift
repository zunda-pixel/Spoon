public import Foundation

/// Classifies FSEvents under a repository into refresh-worthy changes and
/// coalesces bursts, so the UI refreshes once per logical change.
public enum RepoWatcher {
  public enum Change: Sendable, Hashable {
    case refs
    case index
    case worktree
  }

  /// Worktree directories whose churn should never trigger refreshes.
  private static let ignoredWorktreeComponents: Set<String> = [
    ".build", "DerivedData", "node_modules", ".swiftpm",
  ]

  public static func changes(under root: URL) -> AsyncStream<Set<Change>> {
    AsyncStream { continuation in
      let task = Task {
        var pending: Set<Change> = []
        for await batch in FSEventsWatcher.changes(under: root) {
          pending.formUnion(classify(batch, root: root))
          guard !pending.isEmpty else { continue }
          // FSEvents already coalesces 300 ms kernel-side; this small
          // extra window merges callback bursts (e.g. checkout touching
          // refs and worktree separately).
          try? await Task.sleep(for: .milliseconds(200))
          continuation.yield(pending)
          pending = []
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Directory-level classification. Paths arrive as directories that
  /// contain changes, not the changed files themselves.
  static func classify(_ paths: [String], root: URL) -> Set<Change> {
    let rootPath = root.path(percentEncoded: false)
    var changes: Set<Change> = []

    for path in paths {
      guard path.hasPrefix(rootPath) else { continue }
      var relative = String(path.dropFirst(rootPath.count))
      while relative.hasPrefix("/") { relative.removeFirst() }
      while relative.hasSuffix("/") { relative.removeLast() }

      if relative == ".git" {
        // index, HEAD, packed-refs, and MERGE_HEAD all live at .git's top
        // level; directory granularity can't tell them apart.
        changes.insert(.index)
        changes.insert(.refs)
      } else if relative.hasPrefix(".git/refs") {
        changes.insert(.refs)
      } else if relative.hasPrefix(".git") {
        // objects/, logs/, lock churn — refreshing on these causes storms.
        continue
      } else {
        let components = relative.split(separator: "/").map(String.init)
        if components.contains(where: ignoredWorktreeComponents.contains) {
          continue
        }
        changes.insert(.worktree)
      }
    }
    return changes
  }
}
