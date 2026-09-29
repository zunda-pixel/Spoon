import Foundation

/// Reads `git verify-tag --raw` into a `CommitSignature`. GPG prints
/// `[GNUPG:]` status lines; SSH prints ssh-keygen's messages.
enum TagVerificationParser {
  /// `nil` when the tag carries no signature.
  static func parse(_ output: String, exitCode: Int32) -> CommitSignature? {
    if output.contains("no signature found") { return nil }
    let lines = output.split(whereSeparator: \.isNewline).map(String.init)
    if lines.contains(where: { $0.hasPrefix("[GNUPG:]") }) {
      return parseGPG(lines)
    }
    return parseSSH(lines, exitCode: exitCode)
  }

  private static func parseGPG(_ lines: [String]) -> CommitSignature {
    var status = CommitSignature.Status.unverifiable
    var signer: String?
    var key: String?
    var trusted = false
    for line in lines {
      let words = line.split(separator: " ", maxSplits: 3).map(String.init)
      guard words.count >= 2, words[0] == "[GNUPG:]" else { continue }
      let rest = words.count > 3 ? words[3] : nil
      switch words[1] {
      case "GOODSIG": status = .goodUntrusted; key = words[safe: 2]; signer = rest
      case "EXPSIG": status = .expiredSignature; key = words[safe: 2]; signer = rest
      case "EXPKEYSIG": status = .expiredKey; key = words[safe: 2]; signer = rest
      case "REVKEYSIG": status = .revokedKey; key = words[safe: 2]; signer = rest
      case "BADSIG": status = .bad; key = words[safe: 2]; signer = rest
      case "ERRSIG": status = .unverifiable; key = words[safe: 2]
      case "VALIDSIG": key = words[safe: 2] ?? key
      case "TRUST_FULLY", "TRUST_ULTIMATE": trusted = true
      default: break
      }
    }
    if status == .goodUntrusted, trusted { status = .good }
    return CommitSignature(status: status, signer: signer, key: key)
  }

  /// `Good "git" signature for ada@example.com with ED25519 key SHA256:…`,
  /// without "for …" when no allowed signer matches the key.
  private static func parseSSH(_ lines: [String], exitCode: Int32) -> CommitSignature {
    guard let good = lines.first(where: { $0.hasPrefix("Good \"git\" signature") }) else {
      let isBad = lines.contains { $0.contains("incorrect signature") }
      return CommitSignature(status: isBad ? .bad : .unverifiable)
    }
    let key = good.range(of: " key ").map { String(good[$0.upperBound...]) }
    var signer: String?
    if let start = good.range(of: " for "), let end = good.range(of: " with ") {
      signer = String(good[start.upperBound..<end.lowerBound])
    }
    // A valid signature whose key no allowed signer claims.
    let status: CommitSignature.Status = exitCode == 0 && signer != nil ? .good : .goodUntrusted
    return CommitSignature(status: status, signer: signer, key: key)
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
