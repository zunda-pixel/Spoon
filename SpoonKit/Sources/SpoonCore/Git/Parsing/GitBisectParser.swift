import Foundation

/// Parses `git bisect` refs and progress reports (LC_ALL=C keeps the
/// report wording stable).
enum GitBisectParser {
  /// `for-each-ref refs/bisect --format=%(refname)%09%(objectname)`.
  static func parseRefs(_ output: String) -> BisectState {
    var state = BisectState()
    for line in output.split(whereSeparator: \.isNewline) {
      let fields = line.split(separator: "\t")
      guard fields.count == 2, let oid = ObjectID(rawValue: String(fields[1])) else { continue }
      let name = fields[0]
      if name == "refs/bisect/bad" {
        state.badOID = oid
      } else if name.hasPrefix("refs/bisect/good-") {
        state.goodOIDs.append(oid)
      } else if name.hasPrefix("refs/bisect/skip-") {
        state.skippedOIDs.append(oid)
      }
    }
    return state
  }

  /// `<oid> is the first bad commit` ends the search; otherwise git names
  /// the next commit to test as `[<oid>] <subject>`.
  static func parseProgress(_ output: String) -> BisectProgress {
    var next: ObjectID?
    for line in output.split(whereSeparator: \.isNewline) {
      if line.hasSuffix(" is the first bad commit"),
        let oid = ObjectID(rawValue: String(line.split(separator: " ")[0]))
      {
        return .found(oid)
      }
      if next == nil, line.hasPrefix("["), let close = line.firstIndex(of: "]") {
        next = ObjectID(rawValue: String(line[line.index(after: line.startIndex)..<close]))
      }
    }
    return .testing(next)
  }
}
