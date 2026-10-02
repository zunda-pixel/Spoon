import Foundation
public import MemberwiseInit

/// A node of the Changes list's directory tree.
public struct FileTreeNode: Sendable, Hashable, Identifiable {
  /// Display name: one path component, or a folded run like `a/b/c` for
  /// directory chains with a single child.
  public var name: String
  /// Full relative path of this node (directory or file).
  public var path: String
  /// The status entry when this node is a file; nil for directories.
  public var entry: FileStatusEntry?
  /// nil for files, the sorted children for directories.
  public var children: [FileTreeNode]?
  /// The row's identity: its area namespace (the same folder or file can be
  /// in several areas at once, e.g. partly staged) and the display names of
  /// its ancestors, joined by `//`, which a Git path never contains. When
  /// folding changes, a node that moves under another parent gets a new
  /// identity, so the outline removes and inserts its row instead of moving
  /// it across parents, which leaves stale rows drawn over each other.
  public var id: String
}

/// The Changes list's four area trees for one status snapshot, built once
/// per refresh rather than on every render (the natural-order sort is the
/// expensive part).
@MemberwiseInit(.public)
public struct ChangeTrees: Sendable, Hashable {
  public var conflicted: [FileTreeNode]
  public var staged: [FileTreeNode]
  public var unstaged: [FileTreeNode]
  public var untracked: [FileTreeNode]

  public static let empty = ChangeTrees(conflicted: [], staged: [], unstaged: [], untracked: [])

  public init(status: WorkingTreeStatus) {
    conflicted = FileTreeBuilder.build(status.conflictedEntries, namespace: "conflicted")
    staged = FileTreeBuilder.build(status.stagedEntries, namespace: "staged")
    unstaged = FileTreeBuilder.build(status.unstagedEntries, namespace: "unstaged")
    untracked = FileTreeBuilder.build(status.untrackedEntries, namespace: "untracked")
  }
}

/// Builds directory trees from flat status paths. Pure and stateless.
public enum FileTreeBuilder {
  /// Directories sort before files, each alphabetically; single-child
  /// directory chains fold into one node so deep paths stay scannable.
  public static func build(_ entries: [FileStatusEntry], namespace: String = "")
    -> [FileTreeNode]
  {
    let root = Directory()
    for entry in entries {
      let components = entry.path.split(separator: "/").map(String.init)
      guard var fileName = components.last else { continue }
      // A nested repository still arrives as one untracked entry with a
      // trailing slash; keep it so the row reads as a directory.
      if entry.path.hasSuffix("/") {
        fileName += "/"
      }
      var directory = root
      for component in components.dropLast() {
        directory = directory.subdirectory(component)
      }
      directory.files.append((fileName, entry))
    }
    return nodes(of: root, pathPrefix: "", idPrefix: namespace.isEmpty ? "" : "\(namespace)|")
  }

  /// The files of `nodes` in depth-first display order — the flat order
  /// shift-click range selection works over.
  public static func leafEntries(_ nodes: [FileTreeNode]) -> [FileStatusEntry] {
    nodes.flatMap { node in
      if let entry = node.entry {
        [entry]
      } else {
        leafEntries(node.children ?? [])
      }
    }
  }

  private final class Directory {
    var subdirectories: [String: Directory] = [:]
    var files: [(name: String, entry: FileStatusEntry)] = []

    func subdirectory(_ name: String) -> Directory {
      if let existing = subdirectories[name] {
        return existing
      }
      let created = Directory()
      subdirectories[name] = created
      return created
    }
  }

  private static func nodes(
    of directory: Directory, pathPrefix: String, idPrefix: String
  ) -> [FileTreeNode] {
    var result: [FileTreeNode] = []
    for (name, subdirectory) in directory.subdirectories.sorted(by: { compare($0.key, $1.key) }) {
      // Fold chains of empty directories with a single subdirectory.
      var foldedName = name
      var current = subdirectory
      while current.files.isEmpty, current.subdirectories.count == 1,
        let only = current.subdirectories.first
      {
        foldedName += "/\(only.key)"
        current = only.value
      }
      let path = pathPrefix + foldedName
      let id = idPrefix + foldedName
      result.append(
        FileTreeNode(
          name: foldedName,
          path: path,
          children: nodes(of: current, pathPrefix: path + "/", idPrefix: id + "//"),
          id: id
        )
      )
    }
    for (name, entry) in directory.files.sorted(by: { compare($0.name, $1.name) }) {
      result.append(
        FileTreeNode(
          name: name, path: entry.path, entry: entry, children: nil, id: idPrefix + name)
      )
    }
    return result
  }

  private static func compare(_ a: String, _ b: String) -> Bool {
    a.localizedStandardCompare(b) == .orderedAscending
  }
}
