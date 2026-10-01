import Foundation
public import MemberwiseInit

/// How `git commit` records a new commit.
@MemberwiseInit(.public)
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
  public var amend: Bool = false
  /// Add a `Signed-off-by:` trailer for the committer (`--signoff`).
  public var signOff: Bool = false
  public var signing: Signing = .configured
  /// `Key: value` lines git appends to the message (`--trailer`), placing
  /// them after a blank line and merging them with `Signed-off-by:`.
  public var trailers: [String] = []

  var arguments: [String] {
    var arguments: [String] = []
    if amend { arguments.append("--amend") }
    if signOff { arguments.append("--signoff") }
    switch signing {
    case .configured: break
    case .sign: arguments.append("--gpg-sign")
    case .doNotSign: arguments.append("--no-gpg-sign")
    }
    for trailer in trailers {
      arguments += ["--trailer", trailer]
    }
    return arguments
  }
}

/// The repository's commit-signing settings, as git resolves them.
@MemberwiseInit(.public)
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
  public var signsByDefault: Bool = false
  /// `tag.gpgSign`: whether git signs every annotated tag unless told not to.
  public var signsTagsByDefault: Bool = false
  public var format: Format = .openPGP
  /// `user.signingKey`; `nil` lets GPG pick a key from the committer email.
  public var key: String? = nil

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
        configuration.signsByDefault = isTrue(value)
      case "tag.gpgsign":
        configuration.signsTagsByDefault = isTrue(value)
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

  /// git's boolean spellings; a bare `key` line means true.
  private static func isTrue(_ value: String) -> Bool {
    ["", "true", "yes", "on", "1"].contains(value.lowercased())
  }
}

/// Whether `git tag` signs an annotated tag.
public enum TagSigning: Sendable, Hashable {
  /// Follow `tag.gpgSign`.
  case configured
  /// Sign with the configured key (`--sign`).
  case sign
  /// Leave it unsigned even if `tag.gpgSign` is set (`--no-sign`).
  case doNotSign
}

/// Someone credited on a commit with a `Co-authored-by:` trailer, which
/// GitHub and GitLab show as a co-author.
@MemberwiseInit(.public)
public struct CoAuthor: Sendable, Hashable, Identifiable, Codable {
  public var name: String
  public var email: String

  public var id: String { email.lowercased() }

  /// `Ada Lovelace <ada@example.com>`
  public var identity: String { "\(name) <\(email)>" }

  public var trailer: String { "Co-authored-by: \(identity)" }

  /// Reads `Name <email>`; `nil` without both parts.
  public init?(identity: String) {
    let text = identity.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasSuffix(">"), let open = text.lastIndex(of: "<") else { return nil }
    let name = text[..<open].trimmingCharacters(in: .whitespaces)
    let email = text[text.index(after: open)..<text.index(before: text.endIndex)]
      .trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, email.contains("@"), !email.contains(" ") else { return nil }
    self.init(name: name, email: email)
  }
}
