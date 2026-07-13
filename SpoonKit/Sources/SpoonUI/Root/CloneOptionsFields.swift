import SpoonCore
import SwiftUI

/// Partial / filter clone controls for the clone sheet.
@MainActor
struct CloneOptionsFields: View {
  @Binding var filterBlobNone: Bool
  @Binding var shallowClone: Bool
  @Binding var depth: Int
  @Binding var singleBranch: Bool
  @Binding var branchName: String

  var body: some View {
    DisclosureGroup("Clone options") {
      Toggle("Partial clone (skip file contents until needed)", isOn: $filterBlobNone)
      Toggle("Shallow clone", isOn: $shallowClone)
      if shallowClone {
        Stepper(value: $depth, in: 1...10_000) {
          Text("Depth: \(depth)")
        }
      }
      Toggle("Single branch only", isOn: $singleBranch)
      TextField(
        "Branch",
        text: $branchName,
        prompt: Text("Default branch")
      )
    }
  }
}

extension CloneOptionsFields {
  var cloneOptions: CloneOptions {
    CloneOptions(
      filterBlobNone: filterBlobNone,
      depth: shallowClone ? depth : nil,
      singleBranch: singleBranch,
      branch: branchName.isEmpty ? nil : branchName
    )
  }

  var isValid: Bool {
    !shallowClone || depth >= 1
  }
}
