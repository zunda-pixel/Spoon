/// How the object database is stored, from `git count-objects -v`.
public struct RepositoryStorage: Sendable, Hashable {
  /// Objects stored one file each, which `git gc` packs.
  public var looseObjects: Int
  public var looseBytes: Int
  public var packs: Int
  public var packedObjects: Int
  public var packBytes: Int
  /// Files in the object directory that aren't objects or packs.
  public var garbageBytes: Int

  public init(
    looseObjects: Int = 0, looseBytes: Int = 0, packs: Int = 0, packedObjects: Int = 0,
    packBytes: Int = 0, garbageBytes: Int = 0
  ) {
    self.looseObjects = looseObjects
    self.looseBytes = looseBytes
    self.packs = packs
    self.packedObjects = packedObjects
    self.packBytes = packBytes
    self.garbageBytes = garbageBytes
  }

  public var totalBytes: Int { looseBytes + packBytes + garbageBytes }

  /// Parses `git count-objects -v`: `key: value` lines, sizes in KiB.
  static func parse(_ output: String) -> Self {
    var values: [String: Int] = [:]
    for line in output.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: ":", maxSplits: 1)
      guard parts.count == 2, let value = Int(parts[1].drop(while: { $0 == " " })) else {
        continue
      }
      values[String(parts[0])] = value
    }
    return Self(
      looseObjects: values["count"] ?? 0,
      looseBytes: (values["size"] ?? 0) * 1024,
      packs: values["packs"] ?? 0,
      packedObjects: values["in-pack"] ?? 0,
      packBytes: (values["size-pack"] ?? 0) * 1024,
      garbageBytes: (values["size-garbage"] ?? 0) * 1024
    )
  }
}
