import SpoonCore
import SwiftUI

/// Compact verification state of a signed commit. The wording carries the
/// state; the symbol and tint only reinforce it.
@MainActor
struct SignatureBadge: View {
  let signature: CommitSignature

  var body: some View {
    Label(title, systemImage: symbol)
      .foregroundStyle(tint)
      .help(helpText)
      .accessibilityLabel("Signature: \(title)")
      .accessibilityHint(helpText)
  }

  private var title: String {
    switch signature.status {
    case .good: "Verified"
    case .goodUntrusted: "Signed (unknown trust)"
    case .expiredSignature: "Signature expired"
    case .expiredKey: "Signed with expired key"
    case .revokedKey: "Signed with revoked key"
    case .bad: "Bad signature"
    case .unverifiable: "Signed (can’t verify)"
    }
  }

  private var symbol: String {
    switch signature.status {
    case .good: "checkmark.seal.fill"
    case .goodUntrusted, .expiredSignature, .expiredKey: "checkmark.seal"
    case .unverifiable: "questionmark.diamond"
    case .revokedKey, .bad: "xmark.seal.fill"
    }
  }

  private var tint: Color {
    switch signature.status {
    case .good: .green
    case .goodUntrusted, .expiredSignature, .expiredKey, .unverifiable: .secondary
    case .revokedKey, .bad: .red
    }
  }

  private var helpText: String {
    var lines: [String] = []
    if let signer = signature.signer {
      lines.append("Signer: \(signer)")
    }
    if let key = signature.key {
      lines.append("Key: \(key)")
    }
    if signature.status == .unverifiable {
      lines.append(
        "Git could not check this signature, usually because the signing key is not available."
      )
    }
    return lines.isEmpty ? title : lines.joined(separator: "\n")
  }
}
