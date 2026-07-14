import SpoonCore

struct BranchTreeNode: Identifiable {
  let name: String
  let path: String
  let branch: Branch?
  var children: [BranchTreeNode]

  var id: String {
    branch == nil ? "folder:\(path)" : "branch:\(path)"
  }

  static func make(
    from branches: [Branch],
    removingPrefix prefix: String? = nil
  ) -> [BranchTreeNode] {
    var nodes: [BranchTreeNode] = []
    for branch in branches {
      let displayPath =
        if let prefix, branch.name.hasPrefix(prefix) {
          String(branch.name.dropFirst(prefix.count))
        } else {
          branch.name
        }
      insert(
        branch,
        components: displayPath.split(separator: "/")[...],
        parentPath: "",
        into: &nodes
      )
    }
    return nodes.filter { $0.branch != nil } + nodes.filter { $0.branch == nil }
  }

  static func folderPaths(in branchName: String) -> Set<String> {
    let components = branchName.split(separator: "/")
    guard components.count > 1 else { return [] }

    var paths: Set<String> = []
    var path = ""
    for component in components.dropLast() {
      path = path.isEmpty ? String(component) : "\(path)/\(component)"
      paths.insert(path)
    }
    return paths
  }

  private static func insert(
    _ branch: Branch,
    components: ArraySlice<Substring>,
    parentPath: String,
    into nodes: inout [BranchTreeNode]
  ) {
    guard let component = components.first else { return }

    let name = String(component)
    let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
    if components.count == 1 {
      nodes.append(
        BranchTreeNode(name: name, path: path, branch: branch, children: [])
      )
      return
    }

    if let index = nodes.firstIndex(where: { $0.branch == nil && $0.path == path }) {
      insert(
        branch,
        components: components.dropFirst(),
        parentPath: path,
        into: &nodes[index].children
      )
    } else {
      var folder = BranchTreeNode(name: name, path: path, branch: nil, children: [])
      insert(
        branch,
        components: components.dropFirst(),
        parentPath: path,
        into: &folder.children
      )
      nodes.append(folder)
    }
  }
}
