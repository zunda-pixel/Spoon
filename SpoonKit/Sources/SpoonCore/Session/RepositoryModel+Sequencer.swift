extension RepositoryModel {
  public var isSequencing: Bool { sequencerState != nil }

  public func rebasePlan(from commit: Commit) async throws -> RebasePlan {
    guard sequencerState == nil else { throw RebaseSetupError.sequencerActive }
    guard let status else { throw RebaseSetupError.workingTreeNotClean }
    guard status.headBranch != nil else { throw RebaseSetupError.detachedHead }
    guard
      status.stagedEntries.isEmpty,
      status.unstagedEntries.isEmpty,
      status.conflictedEntries.isEmpty
    else { throw RebaseSetupError.workingTreeNotClean }

    let baseOID = commit.parents.first
    let reference = baseOID.map { "\($0.rawValue)..HEAD" } ?? "HEAD"
    let page = try await gitClient.log(LogQuery(reference: reference, maxCount: 1000))
    guard !page.hasMore else { throw RebaseSetupError.rangeTooLarge }
    guard !page.commits.contains(where: \.isMerge) else { throw RebaseSetupError.mergeInRange }
    return RebasePlan(
      steps: page.commits.reversed().map { RebaseStep(action: .pick, commit: $0) },
      baseOID: baseOID
    )
  }

  @discardableResult
  public func interactiveRebase(_ plan: RebasePlan) async -> Bool {
    await perform { try await $0.interactiveRebase(plan) }
  }

  public func cherryPick(_ oid: ObjectID) async {
    await perform { try await $0.cherryPick(oid) }
  }

  public func revert(_ oid: ObjectID) async {
    await perform { try await $0.revert(oid) }
  }

  public func continueSequencer() async {
    guard let kind = sequencerState?.kind else { return }
    await perform { try await $0.continueSequencer(kind) }
  }

  public func skipSequencer() async {
    guard let kind = sequencerState?.kind, kind != .merge else { return }
    await perform { try await $0.skipSequencer(kind) }
  }

  public func abortSequencer() async {
    guard let kind = sequencerState?.kind else { return }
    await perform { try await $0.abortSequencer(kind) }
  }
}
