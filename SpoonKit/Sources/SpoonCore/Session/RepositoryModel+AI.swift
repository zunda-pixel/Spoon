extension RepositoryModel {
  public typealias AIActivity = AIStore.Activity

  public var aiProviders: [AIProviderID: any CodingAgentProvider] {
    get { aiStore.providers }
    set { aiStore.providers = newValue }
  }

  public var aiActivity: AIActivity? { aiStore.activity }
  public var reviewReport: ReviewReport? { aiStore.reviewReport }
  public var aiErrorMessage: String? { aiStore.errorMessage }

  public func clearAIError() {
    aiStore.clearError()
  }

  public func dismissReview() {
    aiStore.dismissReview()
  }

  public func generateCommitMessage(with providerID: AIProviderID) async -> String? {
    await aiStore.generateCommitMessage(
      with: providerID,
      branchName: currentBranch?.name,
      recentSubjects: historyRows.prefix(10).map(\.commit.subject)
    )
  }

  public func runReview(with providerID: AIProviderID) async {
    await aiStore.runReview(with: providerID, branchName: currentBranch?.name)
  }
}
