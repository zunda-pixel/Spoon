import Foundation

/// Parses `git log -1 --format=<signatureFormat>` into a `CommitSignature`.
enum GitSignatureParser {
  /// Verification letter, signer, key ID, and fingerprint, separated by 0x1F.
  static let signatureFormat = "%G?%x1f%GS%x1f%GK%x1f%GF"

  /// `nil` for an unsigned commit (`N`) or unrecognized output.
  static func parse(_ output: String) -> CommitSignature? {
    let fields = output.trimmingCharacters(in: .newlines)
      .split(separator: "\u{1f}", omittingEmptySubsequences: false)
      .map(String.init)
    guard let letter = fields.first else { return nil }
    let status: CommitSignature.Status
    switch letter {
    case "G": status = .good
    case "U": status = .goodUntrusted
    case "X": status = .expiredSignature
    case "Y": status = .expiredKey
    case "R": status = .revokedKey
    case "B": status = .bad
    case "E": status = .unverifiable
    default: return nil
    }
    func field(_ index: Int) -> String? {
      guard fields.indices.contains(index) else { return nil }
      let value = fields[index].trimmingCharacters(in: .whitespaces)
      return value.isEmpty ? nil : value
    }
    return CommitSignature(status: status, signer: field(1), key: field(3) ?? field(2))
  }
}
