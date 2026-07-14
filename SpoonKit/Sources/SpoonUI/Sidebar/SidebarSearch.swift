import Foundation

extension String {
  var hasSidebarSearchQuery: Bool {
    !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func matchesSidebarSearch(_ searchText: String) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty || localizedCaseInsensitiveContains(query)
  }
}
