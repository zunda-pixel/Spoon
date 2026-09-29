/// A commit's GPG, SSH, or X.509 signature as git verified it (`%G?`).
public struct CommitSignature: Sendable, Hashable {
  public enum Status: Sendable, Hashable {
    /// `G`: valid and from a trusted key.
    case good
    /// `U`: valid, but the key's trust is unknown.
    case goodUntrusted
    /// `X`: valid, but the signature has expired.
    case expiredSignature
    /// `Y`: valid, but made by a key that has since expired.
    case expiredKey
    /// `R`: made by a key that has been revoked.
    case revokedKey
    /// `B`: the signature does not match the commit.
    case bad
    /// `E`: git could not check it, typically because the key is missing.
    case unverifiable

    /// The signature matches the commit's content.
    public var isValid: Bool {
      switch self {
      case .good, .goodUntrusted, .expiredSignature, .expiredKey: true
      case .revokedKey, .bad, .unverifiable: false
      }
    }
  }

  public var status: Status
  /// Signer as the key identifies it (`%GS`), when known.
  public var signer: String?
  /// Key ID (`%GK`) or fingerprint (`%GF`), when known.
  public var key: String?

  public init(status: Status, signer: String? = nil, key: String? = nil) {
    self.status = status
    self.signer = signer
    self.key = key
  }
}
