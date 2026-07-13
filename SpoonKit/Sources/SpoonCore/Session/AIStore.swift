import Foundation
public import Observation

/// Owns coding-agent activity, errors, and review output for one repository.
@MainActor
@Observable
public final class AIStore {
  public enum Activity: Sendable, Hashable {
    case generatingCommitMessage(AIProviderID)
    case reviewing(AIProviderID)
  }

  public var providers: [AIProviderID: any CodingAgentProvider] = [:]
  public private(set) var activity: Activity?
  public private(set) var reviewReport: ReviewReport?
  public private(set) var errorMessage: String?

  private let repositoryURL: URL
  private let gitClient: any GitClient

  init(repositoryURL: URL, gitClient: any GitClient) {
    self.repositoryURL = repositoryURL
    self.gitClient = gitClient
  }

  public func clearError() {
    errorMessage = nil
  }

  public func dismissReview() {
    reviewReport = nil
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
        throw AIError(kind: .nothingToReview)
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

  func runReview(with providerID: AIProviderID, branchName: String?) async {
    guard let provider = providers[providerID], activity == nil else { return }
    activity = .reviewing(providerID)
    defer { activity = nil }
    do {
      let defaultBranch = try await gitClient.defaultBranch()
      let diff: String
      let baseDescription: String
      if let branchName, branchName != defaultBranch {
        let base = try await gitClient.mergeBase(defaultBranch, "HEAD")
        diff = try await gitClient.diffText(from: base.rawValue, to: "HEAD")
        baseDescription = "\(defaultBranch) (merge-base \(base.shortened))"
      } else {
        diff = try await gitClient.stagedDiffText()
        baseDescription = "the index (staged changes)"
      }
      guard !diff.isEmpty else {
        throw AIError(kind: .nothingToReview)
      }
      let context = PromptBuilder.ReviewContext(
        branchName: branchName,
        baseReference: baseDescription,
        diff: diff,
        guidelines: PromptBuilder.guidelines(in: repositoryURL)
      )
      reviewReport = try await provider.review(
        prompt: PromptBuilder.reviewPrompt(context),
        repository: repositoryURL
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
