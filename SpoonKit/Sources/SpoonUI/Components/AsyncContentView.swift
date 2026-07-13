import SwiftUI

enum AsyncLoadState<Value> {
  case loading
  case loaded(Value)
  case failed(String)
}

struct AsyncContentView<Value, Content: View, Empty: View>: View {
  let state: AsyncLoadState<Value>
  let isEmpty: (Value) -> Bool
  @ViewBuilder let content: (Value) -> Content
  @ViewBuilder let empty: Empty
  let errorTitle: String

  var body: some View {
    switch state {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .loaded(let value):
      if isEmpty(value) {
        empty
      } else {
        content(value)
      }
    case .failed(let message):
      ContentUnavailableView(
        errorTitle,
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    }
  }
}
