import Foundation

enum GitRemoteParser {
  /// Parses `git remote -v`, preserving the order in which remotes appear.
  static func parse(_ text: String) -> [Remote] {
    var byName: [String: Remote] = [:]
    var order: [String] = []
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: "\t", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let name = String(parts[0])
      let rest = parts[1]
      let isPush = rest.hasSuffix(" (push)")
      let url = String(
        rest
          .replacingOccurrences(of: " (fetch)", with: "")
          .replacingOccurrences(of: " (push)", with: "")
      )
      if var existing = byName[name] {
        if isPush, existing.fetchURL != url {
          existing.pushURL = url
        }
        byName[name] = existing
      } else {
        byName[name] = Remote(name: name, fetchURL: url)
        order.append(name)
      }
    }
    return order.compactMap { byName[$0] }
  }
}
