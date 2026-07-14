import SpoonCore

struct RemoteTagSelection: Identifiable {
  let tag: Tag
  let remote: Remote

  var id: String { "\(remote.name)\u{0}\(tag.name)" }
}

struct RemoteBranchSelection: Hashable, Identifiable {
  let remote: Remote
  let branch: Branch

  var fullName: String { branch.name }

  var localName: String {
    let prefix = "\(remote.name)/"
    return fullName.hasPrefix(prefix) ? String(fullName.dropFirst(prefix.count)) : fullName
  }

  var id: String { "\(remote.name)\u{0}\(branch.name)" }
}
