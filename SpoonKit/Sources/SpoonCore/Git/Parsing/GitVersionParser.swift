enum GitVersionParser {
  /// Parses `git version` output such as `git version 2.49.0`,
  /// `git version 2.39.5 (Apple Git-154)`, or `git version 2.56.0.rc2`.
  static func parse(_ output: String) -> GitVersion? {
    let fields = output.split(whereSeparator: { !$0.isNumber && $0 != "." })
    guard let field = fields.first(where: { $0.contains(".") }) else { return nil }
    let components = field.split(separator: ".").prefix(3).compactMap { Int($0) }
    guard components.count >= 2 else { return nil }
    return GitVersion(components[0], components[1], components.count > 2 ? components[2] : 0)
  }
}
