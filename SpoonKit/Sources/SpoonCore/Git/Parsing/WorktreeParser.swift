public import Foundation

/// Parses `git worktree list --porcelain` into `[Worktree]`.
/// Pure and stateless — fixture-tested byte-for-byte.
public enum WorktreeParser {
  public static func parse(_ data: Data) -> [Worktree] {
    let text = String(decoding: data, as: UTF8.self)
    var worktrees: [Worktree] = []
    var path: URL?
    var head: ObjectID?
    var branch: String?

    func flush() {
      if let root = path {
        worktrees.append(
          Worktree(path: root, branch: branch, headOID: head, isMain: worktrees.isEmpty)
        )
      }
      path = nil
      head = nil
      branch = nil
    }

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.isEmpty {
        flush()
      } else if line.hasPrefix("worktree ") {
        path = URL(filePath: String(line.dropFirst("worktree ".count)), directoryHint: .isDirectory)
      } else if line.hasPrefix("HEAD ") {
        head = ObjectID(rawValue: String(line.dropFirst("HEAD ".count)))
      } else if line.hasPrefix("branch ") {
        let ref = line.dropFirst("branch ".count)
        branch = String(ref.hasPrefix("refs/heads/") ? ref.dropFirst("refs/heads/".count) : ref)
      }
      // "detached", "bare", "locked", "prunable …" carry no fields we model.
    }
    flush()
    return worktrees
  }
}
