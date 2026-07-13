public import Foundation
import HTTPTypes
import HTTPTypesFoundation

/// Transport seam so tests can replay recorded GraphQL responses.
public protocol GitHubTransport: Sendable {
  func post(_ url: URL, headers: [String: String], body: Data) async throws -> (
    status: Int, body: Data
  )
}

public struct URLSessionGitHubTransport: GitHubTransport {
  public init() {}

  public func post(_ url: URL, headers: [String: String], body: Data) async throws -> (
    status: Int, body: Data
  ) {
    var request = HTTPRequest(method: .post, url: url)
    for (name, value) in headers {
      if let field = HTTPField.Name(name) {
        request.headerFields[field] = value
      }
    }
    let (data, response) = try await URLSession.shared.upload(for: request, from: body)
    return (response.status.code, data)
  }
}

public struct GitHubError: Error, Sendable, LocalizedError {
  public enum Kind: Sendable, Equatable {
    case unauthenticated
    case rateLimited(resetAt: Date?)
    case graphQL(message: String)
    case http(status: Int)
    case decoding
  }

  public var kind: Kind

  public init(kind: Kind) {
    self.kind = kind
  }

  public var errorDescription: String? {
    switch kind {
    case .unauthenticated:
      "Not signed in to GitHub. Sign in with `gh auth login` or add a token in Settings."
    case .rateLimited:
      "GitHub rate limit reached — PR data is paused and will resume automatically."
    case .graphQL(let message):
      "GitHub API error: \(message)"
    case .http(let status):
      "GitHub returned HTTP \(status)."
    case .decoding:
      "Could not read GitHub's response."
    }
  }
}

/// Minimal GraphQL client for the PR sync hot path.
public actor GitHubAPIClient {
  private let transport: any GitHubTransport
  private let tokenProvider: any GitHubTokenProvider
  private let endpoint = URL(string: "https://api.github.com/graphql")!

  public init(
    tokenProvider: any GitHubTokenProvider,
    transport: any GitHubTransport = URLSessionGitHubTransport()
  ) {
    self.tokenProvider = tokenProvider
    self.transport = transport
  }

  struct GraphQLPayload: Encodable {
    var query: String
    var variables: [String: String?]
  }

  struct GraphQLEnvelope<T: Decodable>: Decodable {
    struct GraphQLMessage: Decodable {
      var message: String
    }

    var data: T?
    var errors: [GraphQLMessage]?
  }

  /// Runs one query and decodes `data` as `T`. Throws typed errors for
  /// auth, rate-limit, and API failures.
  public func query<T: Decodable & Sendable>(
    _ query: String,
    variables: [String: String?],
    as type: T.Type
  ) async throws -> T {
    guard let token = await tokenProvider.token() else {
      throw GitHubError(kind: .unauthenticated)
    }

    let payload = try JSONEncoder().encode(GraphQLPayload(query: query, variables: variables))
    let (status, body) = try await transport.post(
      endpoint,
      headers: [
        "Authorization": "Bearer \(token)",
        "Content-Type": "application/json",
        "User-Agent": "Spoon",
      ],
      body: payload
    )

    switch status {
    case 200:
      break
    case 401:
      throw GitHubError(kind: .unauthenticated)
    case 403, 429:
      throw GitHubError(kind: .rateLimited(resetAt: nil))
    default:
      throw GitHubError(kind: .http(status: status))
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let envelope = try? decoder.decode(GraphQLEnvelope<T>.self, from: body) else {
      throw GitHubError(kind: .decoding)
    }
    if let message = envelope.errors?.first?.message {
      throw GitHubError(kind: .graphQL(message: message))
    }
    guard let data = envelope.data else {
      throw GitHubError(kind: .decoding)
    }
    return data
  }
}
