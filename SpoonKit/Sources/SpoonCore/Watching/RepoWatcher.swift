public import Foundation

/// Classifies FSEvents under a repository into refresh-worthy changes and
/// coalesces bursts, so the UI refreshes once per logical change.
public enum RepoWatcher {
  public enum Change: Sendable, Hashable {
    case refs
    case index
    case worktree
  }

  /// Where one checkout keeps its files and git metadata. A linked worktree
  /// keeps HEAD and its index in a per-worktree git directory, while refs
  /// live in the repository's shared common directory; both can sit outside
  /// the worktree root.
  public struct Layout: Sendable, Hashable {
    public var root: URL
    public var gitDirectory: URL
    public var commonDirectory: URL

    public init(root: URL, gitDirectory: URL, commonDirectory: URL) {
      self.root = root
      self.gitDirectory = gitDirectory
      self.commonDirectory = commonDirectory
    }

    /// A non-linked checkout whose metadata is `<root>/.git`.
    public init(root: URL) {
      let dotGit = root.appending(path: ".git", directoryHint: .isDirectory)
      self.init(root: root, gitDirectory: dotGit, commonDirectory: dotGit)
    }

    public init(root: URL, paths: GitRepositoryPaths) {
      self.init(
        root: root,
        gitDirectory: paths.gitDirectory,
        commonDirectory: paths.commonDirectory
      )
    }

    /// The fewest directories whose subtrees cover the whole layout.
    var watchedDirectories: [URL] {
      var directories: [URL] = []
      for directory in [root, gitDirectory, commonDirectory]
      where !directories.contains(where: { Self.path(directory, isWithin: $0) }) {
        directories.removeAll { Self.path($0, isWithin: directory) }
        directories.append(directory)
      }
      return directories
    }

    private static func path(_ url: URL, isWithin ancestor: URL) -> Bool {
      RepoWatcher.relativePath(of: url.path(percentEncoded: false), under: ancestor) != nil
    }
  }

  /// Worktree directories whose churn should never trigger refreshes.
  private static let ignoredWorktreeComponents: Set<String> = [
    ".build", "DerivedData", "node_modules", ".swiftpm",
  ]

  public static func changes(in layout: Layout) -> AsyncStream<Set<Change>> {
    AsyncStream { continuation in
      let task = Task {
        var pending: Set<Change> = []
        for await batch in FSEventsWatcher.changes(under: layout.watchedDirectories) {
          pending.formUnion(classify(batch, layout: layout))
          guard !pending.isEmpty else { continue }
          // FSEvents already coalesces 300 ms kernel-side; this small
          // extra window merges callback bursts (e.g. branch switching touching
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
  static func classify(_ paths: [String], layout: Layout) -> Set<Change> {
    var changes: Set<Change> = []

    for path in paths {
      if let relative = relativePath(of: path, under: layout.gitDirectory) {
        if relative.isEmpty {
          // index, HEAD, and MERGE_HEAD all live at the git directory's top
          // level; directory granularity can't tell them apart.
          changes.insert(.index)
          changes.insert(.refs)
        } else if layout.gitDirectory == layout.commonDirectory, isRefsPath(relative) {
          changes.insert(.refs)
        }
        // objects/, logs/, lock churn — refreshing on these causes storms.
      } else if let relative = relativePath(of: path, under: layout.commonDirectory) {
        // packed-refs sits at the common directory's top level. Other
        // worktrees' HEAD and index churn under worktrees/ is not ours.
        if relative.isEmpty || isRefsPath(relative) {
          changes.insert(.refs)
        }
      } else if let relative = relativePath(of: path, under: layout.root) {
        let components = relative.split(separator: "/").map(String.init)
        if components.first == ".git"
          || components.contains(where: ignoredWorktreeComponents.contains)
        {
          continue
        }
        changes.insert(.worktree)
      }
    }
    return changes
  }

  private static func isRefsPath(_ relative: String) -> Bool {
    relative == "refs" || relative.hasPrefix("refs/")
  }

  /// `path` relative to `directory` without surrounding slashes, `""` for
  /// the directory itself, or `nil` when `path` lies outside it.
  private static func relativePath(of path: String, under directory: URL) -> String? {
    var base = directory.path(percentEncoded: false)
    while base.count > 1, base.hasSuffix("/") { base.removeLast() }
    guard path == base || path.hasPrefix(base == "/" ? base : base + "/") else { return nil }
    var relative = String(path.dropFirst(base.count))
    while relative.hasPrefix("/") { relative.removeFirst() }
    while relative.hasSuffix("/") { relative.removeLast() }
    return relative
  }
}
