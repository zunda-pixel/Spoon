import Foundation
public import Observation

/// Owns coding-agent activity and errors for one repository.
@MainActor
@Observable
public final class AIStore {
  public enum Activity: Sendable, Hashable {
    case generatingCommitMessage(AIProviderID)
  }

  public var providers: [AIProviderID: any CodingAgentProvider] = [:]
  public private(set) var activity: Activity?
  public private(set) var errorMessage: String?

  private let gitClient: any GitClient

  init(gitClient: any GitClient) {
    self.gitClient = gitClient
  }

  public func clearError() {
    errorMessage = nil
  }

  func generateCommitMessage(
    with providerID: AIProviderID,
    branchName: String?,
    recentSubjects: [String]
  ) async -> String? {
    guard let provider = providers[providerID], activity == nil else { return nil }
    activity = .generatingCommitMessage(providerID)
    defer { activity = nil }
    do {
      let diff = try await gitClient.stagedDiffText()
      guard !diff.isEmpty else {
        throw AIError(kind: .noChanges)
      }
      let context = PromptBuilder.CommitContext(
        branchName: branchName,
        recentSubjects: recentSubjects,
        stagedDiff: diff
      )
      let message = try await provider.generateCommitMessage(
        prompt: PromptBuilder.commitMessagePrompt(context)
      )
      errorMessage = nil
      return message
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }
}
