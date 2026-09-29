import Testing

@testable import SpoonCore

@Suite("Tag verification parsing")
struct TagVerificationParserTests {
  private let key = "SHA256:SntVsOlU7pknkUC7pt8H9MOUPO5qH4pLpUKwCGUocnc"

  @Test func sshResults() {
    let good = TagVerificationParser.parse(
      "Good \"git\" signature for ada@example.com with ED25519 key \(key)\n", exitCode: 0)
    #expect(good == CommitSignature(status: .good, signer: "ada@example.com", key: key))

    let unknownSigner = TagVerificationParser.parse(
      """
      Good "git" signature with ED25519 key \(key)
      No principal matched.
      """, exitCode: 1)
    #expect(unknownSigner == CommitSignature(status: .goodUntrusted, key: key))

    let bad = TagVerificationParser.parse(
      "Could not verify signature.\nSignature verification failed: incorrect signature\n",
      exitCode: 1)
    #expect(bad?.status == .bad)
    #expect(TagVerificationParser.parse("error: no signature found\n", exitCode: 1) == nil)
    #expect(TagVerificationParser.parse("gpg: failed\n", exitCode: 1)?.status == .unverifiable)
  }

  @Test func gpgStatusLines() {
    let trusted = TagVerificationParser.parse(
      """
      [GNUPG:] NEWSIG
      [GNUPG:] GOODSIG 1234ABCD Ada Lovelace <ada@example.com>
      [GNUPG:] VALIDSIG FINGERPRINT0001 2026-09-30
      [GNUPG:] TRUST_ULTIMATE 0 pgp
      """, exitCode: 0)
    #expect(
      trusted
        == CommitSignature(
          status: .good, signer: "Ada Lovelace <ada@example.com>", key: "FINGERPRINT0001"))

    let untrusted = TagVerificationParser.parse(
      "[GNUPG:] GOODSIG 1234ABCD Ada\n[GNUPG:] TRUST_UNDEFINED 0 pgp\n", exitCode: 0)
    #expect(untrusted?.status == .goodUntrusted)
    #expect(
      TagVerificationParser.parse("[GNUPG:] BADSIG 1234ABCD Ada\n", exitCode: 1)?.status == .bad)
    #expect(
      TagVerificationParser.parse("[GNUPG:] ERRSIG 1234ABCD 1 8 00 1700000000 9\n", exitCode: 1)?
        .status == .unverifiable)
    #expect(
      TagVerificationParser.parse("[GNUPG:] EXPKEYSIG 1234ABCD Ada\n", exitCode: 1)?.status
        == .expiredKey)
  }
}
