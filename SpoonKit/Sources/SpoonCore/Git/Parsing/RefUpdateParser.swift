/// Parses `update <ref> <new-oid> <old-oid>` lines — the `git update-ref
/// --stdin` format that `git history --dry-run` and `git replay` print.
enum RefUpdateParser {
  static func parse(_ output: String) -> [RefUpdate] {
    output.split(whereSeparator: \.isNewline).compactMap { line in
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      guard
        fields.count == 4, fields[0] == "update",
        let newOID = ObjectID(rawValue: String(fields[2])),
        let oldOID = ObjectID(rawValue: String(fields[3]))
      else { return nil }
      return RefUpdate(reference: String(fields[1]), newOID: newOID, oldOID: oldOID)
    }
  }
}
