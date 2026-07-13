enum GitVersionParser {
  static func supportsBackfill(_ output: String) -> Bool {
    let fields = output.split(whereSeparator: { !$0.isNumber && $0 != "." })
    guard let version = fields.first(where: { $0.contains(".") }) else { return false }
    let components = version.split(separator: ".").compactMap { Int($0) }
    guard components.count >= 2 else { return false }
    return components[0] > 2 || (components[0] == 2 && components[1] >= 49)
  }
}
