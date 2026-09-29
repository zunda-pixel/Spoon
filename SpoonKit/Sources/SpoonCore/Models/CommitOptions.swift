/// How `git commit` records a new commit.
public struct CommitOptions: Sendable, Hashable {
  public enum Signing: Sendable, Hashable {
    /// Follow `commit.gpgSign`.
    case configured
    /// Sign with the configured key (`--gpg-sign`), whatever the config says.
    case sign
    /// Leave the commit unsigned (`--no-gpg-sign`).
    case doNotSign
  }

  /// Replace the tip commit instead of adding one.
  public var amend: Bool
  /// Add a `Signed-off-by:` trailer for the committer (`--signoff`).
  public var signOff: Bool
  public var signing: Signing

  public init(amend: Bool = false, signOff: Bool = false, signing: Signing = .configured) {
    self.amend = amend
    self.signOff = signOff
    self.signing = signing
  }

  var arguments: [String] {
    var arguments: [String] = []
    if amend { arguments.append("--amend") }
    if signOff { arguments.append("--signoff") }
    switch signing {
    case .configured: break
    case .sign: arguments.append("--gpg-sign")
    case .doNotSign: arguments.append("--no-gpg-sign")
    }
    return arguments
  }
}

/// The repository's commit-signing settings, as git resolves them.
public struct CommitSigningConfiguration: Sendable, Hashable {
  public enum Format: String, Sendable, Hashable {
    case openPGP = "openpgp"
    case ssh
    case x509

    public var displayName: String {
      switch self {
      case .openPGP: "GPG"
      case .ssh: "SSH"
      case .x509: "X.509"
      }
    }
  }

  /// `commit.gpgSign`: whether git signs every commit unless told not to.
  public var signsByDefault: Bool
  public var format: Format
  /// `user.signingKey`; `nil` lets GPG pick a key from the committer email.
  public var key: String?

  public init(signsByDefault: Bool = false, format: Format = .openPGP, key: String? = nil) {
    self.signsByDefault = signsByDefault
    self.format = format
    self.key = key
  }

  /// SSH and X.509 signing need an explicit key; GPG can find one itself.
  public var canSign: Bool {
    format == .openPGP || key != nil
  }

  /// Parses `git config --get-regexp` output: one `key value` per line,
  /// keys lowercased by git. Later lines win, as in git.
  static func parse(_ output: String) -> Self {
    var configuration = Self()
    for line in output.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: " ", maxSplits: 1)
      guard let name = parts.first else { continue }
      let value = parts.count > 1 ? String(parts[1]) : ""
      switch name.lowercased() {
      case "commit.gpgsign":
        // A bare `key` line means true, as in git.
        configuration.signsByDefault = ["", "true", "yes", "on", "1"].contains(value.lowercased())
      case "gpg.format":
        configuration.format = Format(rawValue: value.lowercased()) ?? .openPGP
      case "user.signingkey":
        configuration.key = value.isEmpty ? nil : value
      default:
        break
      }
    }
    return configuration
  }
}
