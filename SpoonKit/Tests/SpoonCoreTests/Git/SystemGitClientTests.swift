import Foundation
import Testing

@testable import SpoonCore

@Suite("SystemGitClient")
struct SystemGitClientTests {
  private let root = URL(filePath: "/tmp/fake-repo")
  private let git = URL(filePath: "/usr/bin/git")

  private func makeClient(_ runner: FakeCommandRunner) -> SystemGitClient {
    SystemGitClient(repositoryRoot: root, git: git, runner: runner)
  }

  @Test func statusSendsExactArgvAndEnvironment() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "status", "--porcelain=v2", "--branch", "--show-stash", "-z",
      ],
      stdout: "# branch.oid 4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331\u{0}# branch.head main\u{0}"
    )

    let status = try await makeClient(runner).status()
    #expect(status.headBranch == "main")

    let command = try #require(runner.invocations.first)
    #expect(command.executable == git)
    #expect(command.workingDirectory == root)
    #expect(command.environment["GIT_TERMINAL_PROMPT"] == "0")
    #expect(command.environment["GIT_OPTIONAL_LOCKS"] == "0")
    #expect(command.environment["LC_ALL"] == "C")
  }

  @Test func branchesSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "for-each-ref", "refs/heads",
        "--sort=-committerdate",
        "--format=\(GitRefParser.branchFormat)",
      ],
      stdout:
        "*\u{0}main\u{0}4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331\u{0}subject\u{0}\u{0}\u{0}1720000000\n"
    )

    let branches = try await makeClient(runner).branches()
    #expect(branches.count == 1)
    #expect(branches[0].isCurrent)
  }

  @Test func nonZeroExitBecomesCommandError() async {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "status", "--porcelain=v2", "--branch", "--show-stash", "-z",
      ],
      stderr: "fatal: not a git repository\n",
      exitCode: 128
    )

    await #expect(throws: CommandError.self) {
      try await makeClient(runner).status()
    }
  }

  @Test func remoteManagementSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "remote", "add", "origin", "https://github.com/o/r.git",
      ]
    )
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "remote", "set-url", "origin", "https://github.com/o/new.git",
      ]
    )
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "remote", "set-url", "--push", "origin", "git@github.com:o/new.git",
      ]
    )
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "remote", "remove", "origin",
      ]
    )
    let client = makeClient(runner)
    try await client.addRemote(name: "origin", url: "https://github.com/o/r.git")
    try await client.setRemoteURL(
      name: "origin",
      fetchURL: "https://github.com/o/new.git",
      pushURL: "git@github.com:o/new.git"
    )
    try await client.removeRemote(name: "origin")
    #expect(runner.invocations.count == 4)
  }

  @Test func remotesSendsExactArgvAndPreservesDistinctURLs() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["remote", "-v"],
      stdout: """
        origin\thttps://example.com/fetch.git (fetch)
        origin\tssh://git@example.com/push.git (push)

        """
    )

    let remotes = try await makeClient(runner).remotes()

    #expect(remotes.count == 1)
    #expect(remotes[0].fetchURL == "https://example.com/fetch.git")
    #expect(remotes[0].pushURL == "ssh://git@example.com/push.git")
    #expect(runner.invocations.count == 1)
  }

  @Test func backfillCapabilityAndCommandSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version 2.49.1\n")
    runner.stub(arguments: baseFlags + ["backfill"])
    let client = makeClient(runner)

    #expect(await client.capabilities().supportsBackfill)
    try await client.backfill()

    #expect(runner.invocations.count == 2)
  }

  @Test func capabilitiesRunGitVersionOnce() async {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version 2.56.0\n")
    let client = makeClient(runner)

    #expect(await client.capabilities().version == GitVersion(2, 56, 0))
    #expect(await client.capabilities().version == GitVersion(2, 56, 0))

    #expect(runner.invocations.count == 1)
  }

  @Test func repositoryPathsUseRepoInfoOnGit256() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version 2.56.0\n")
    runner.stub(
      arguments: baseFlags + [
        "repo", "info", "-z", "path.gitdir.absolute", "path.commondir.absolute",
      ],
      stdout: "path.gitdir.absolute\n/repo/.git/worktrees/wt\u{0}"
        + "path.commondir.absolute\n/repo/.git\u{0}"
    )

    let paths = try await makeClient(runner).repositoryPaths()

    #expect(paths.gitDirectory.path == "/repo/.git/worktrees/wt")
    #expect(paths.commonDirectory.path == "/repo/.git")
  }

  @Test func repositoryPathsFallBackToRevParse() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version 2.55.0\n")
    runner.stub(
      arguments: baseFlags + [
        "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir",
      ],
      stdout: "/repo/.git\n/repo/.git\n"
    )

    let paths = try await makeClient(runner).repositoryPaths()

    #expect(paths.gitDirectory.path == "/repo/.git")
    #expect(paths.commonDirectory.path == "/repo/.git")
  }

  @Test func dropCommitSendsExactArgvAndParsesDryRun() async throws {
    let runner = FakeCommandRunner()
    let oid = String(repeating: "a", count: 40)
    runner.stub(
      arguments: baseFlags + ["history", "drop", "--dry-run", oid],
      stdout: "update refs/heads/main \(String(repeating: "b", count: 40)) "
        + "\(String(repeating: "c", count: 40))\n"
    )
    runner.stub(arguments: baseFlags + ["history", "drop", oid])
    let client = makeClient(runner)
    let target = try #require(ObjectID(rawValue: oid))

    let preview = try await client.dropCommit(target, dryRun: true)
    try await client.dropCommit(target, dryRun: false)

    #expect(preview.map(\.branchName) == ["main"])
    #expect(runner.invocations.count == 2)
  }

  @Test func deleteMergedBranchesSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["branch", "--delete-merged", "**", "--dry-run"],
      stdout: "Would delete branch feature/a (was 1234567).\n"
        + "Would delete branch b (was 89abcde).\n",
      stderr: "Skipping 'keep' (branch.keep.deleteMerged is false)\n"
    )
    runner.stub(
      arguments: baseFlags + ["branch", "--delete-merged", "**", "feature/a", "b"],
      stdout: "Deleted branch feature/a (was 1234567).\n"
    )
    let client = makeClient(runner)

    let preview = try await client.deleteMergedBranches(branches: [], dryRun: true)
    let deleted = try await client.deleteMergedBranches(branches: preview, dryRun: false)

    #expect(preview == ["feature/a", "b"])
    #expect(deleted == ["feature/a"])
  }

  @Test func forkedBranchesUseGitBranchForkedOnGit256() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version 2.56.0\n")
    runner.stub(
      arguments: baseFlags + [
        "branch", "--format=%(refname:short)", "--forked", "refs/remotes/origin/main",
      ],
      stdout: "feature/a\nfeature/b\n"
    )

    let names = try await makeClient(runner).branchNames(forkedFrom: "refs/remotes/origin/main")

    #expect(names == ["feature/a", "feature/b"])
  }

  @Test func forkedBranchesFallBackToUpstreamRefs() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version 2.55.0\n")
    runner.stub(
      arguments: baseFlags + [
        "for-each-ref", "refs/heads", "--format=%(refname:short)%09%(upstream)",
      ],
      stdout: "main\trefs/remotes/origin/main\nfeature/a\trefs/heads/main\nloose\t\n"
    )

    let names = try await makeClient(runner).branchNames(forkedFrom: "refs/heads/main")

    #expect(names == ["feature/a"])
  }

  @Test(arguments: [("2.56.0", true), ("2.55.0", false)])
  func moveBranchVerifiesTheExpectedTip(version: String, usesRefsCommand: Bool) async throws {
    let runner = FakeCommandRunner()
    let target = try #require(ObjectID(rawValue: String(repeating: "a", count: 40)))
    let tip = try #require(ObjectID(rawValue: String(repeating: "b", count: 40)))
    let message = "spoon: move topic to aaaaaaa"
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version \(version)\n")
    runner.stub(
      arguments: baseFlags
        + (usesRefsCommand
          ? ["refs", "update", "--message=\(message)"] : ["update-ref", "-m", message])
        + ["refs/heads/topic", target.rawValue, tip.rawValue]
    )

    try await makeClient(runner).moveBranch(name: "topic", to: target, expectedTip: tip)

    #expect(runner.invocations.count == 2)
  }

  @Test func replayBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    let base = try #require(ObjectID(rawValue: String(repeating: "a", count: 40)))
    let replay = ["replay", "--onto=\(base.rawValue)", "--ref-action=update"]
    runner.stub(arguments: baseFlags + replay + ["\(base.rawValue)..refs/heads/topic"])
    runner.stub(
      arguments: baseFlags + replay + ["--linearize", "\(base.rawValue)..refs/heads/topic"]
    )
    let client = makeClient(runner)

    try await client.replayBranch("topic", onto: base, linearize: false)
    try await client.replayBranch("topic", onto: base, linearize: true)

    #expect(runner.invocations.count == 2)
  }

  @Test func partialCloneRemoteReadsExtensionConfig() async throws {
    let runner = FakeCommandRunner()
    let key = baseFlags + ["config", "--get", "extensions.partialClone"]
    runner.stub(arguments: key, stdout: "origin\n")
    #expect(try await makeClient(runner).partialCloneRemote() == "origin")

    let fullClone = FakeCommandRunner()
    fullClone.stub(arguments: key, exitCode: 1)
    #expect(try await makeClient(fullClone).partialCloneRemote() == nil)
  }

  @Test func dropLargeBlobsSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "repack", "-a", "-d", "--drop-filtered", "--filter=blob:limit=1048576",
        "--no-write-bitmap-index",
      ]
    )

    try await makeClient(runner).dropLargeBlobs(largerThan: 1_048_576)

    let command = try #require(runner.invocations.first)
    #expect(command.timeout == .seconds(3600))
  }

  @Test func missingObjectsAndRemoteSizesSendExactArgvAndStdin() async throws {
    let runner = FakeCommandRunner()
    let first = String(repeating: "a", count: 40)
    let second = String(repeating: "b", count: 40)
    runner.stub(
      arguments: baseFlags + [
        "rev-list", "--objects", "--missing=print", "--missing-only", "HEAD",
      ],
      stdout: "\(first)\n\(second)\n"
    )
    runner.stub(
      arguments: baseFlags + ["cat-file", "--batch-command=%(objectname) %(objectsize)"],
      stdout: "\(first) 120\n\(second) 3000\n"
    )
    let client = makeClient(runner)

    let missing = try await client.missingObjectIDs()
    let sizes = try await client.remoteObjectSizes(of: missing, from: "origin")

    #expect(missing.map(\.rawValue) == [first, second])
    #expect(sizes.values.reduce(0, +) == 3120)
    let command = try #require(runner.invocations.last)
    #expect(
      command.standardInput == Data("remote-object-info origin \(first) \(second)\n".utf8)
    )
  }

  @Test func mergePreviewReadsConflictedPathsFromMergeTree() async throws {
    let arguments =
      baseFlags + [
        "merge-tree", "--write-tree", "--name-only", "--no-messages", "-z", "HEAD", "topic",
      ]
    let tree = String(repeating: "a", count: 40)
    let clean = FakeCommandRunner()
    clean.stub(arguments: arguments, stdout: "\(tree)\u{0}")
    let conflicted = FakeCommandRunner()
    conflicted.stub(
      arguments: arguments,
      stdout: "\(tree)\u{0}README.md\u{0}Sources/My File.swift\u{0}",
      exitCode: 1
    )
    let failing = FakeCommandRunner()
    failing.stub(arguments: arguments, stderr: "fatal: refusing to merge\n", exitCode: 128)

    #expect(try await makeClient(clean).mergePreview(branch: "topic").isClean)
    #expect(
      try await makeClient(conflicted).mergePreview(branch: "topic").conflictedPaths
        == ["README.md", "Sources/My File.swift"]
    )
    await #expect(throws: CommandError.self) {
      try await makeClient(failing).mergePreview(branch: "topic")
    }
  }

  @Test(arguments: [("2.56.0", ["add", "--resolved", "--"]), ("2.55.0", ["add", "--"])])
  func markResolvedUsesAddResolvedOnGit256(version: String, command: [String]) async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "git version \(version)\n")
    runner.stub(arguments: baseFlags + command + ["a.txt"])

    try await makeClient(runner).markResolved(paths: ["a.txt"])

    #expect(runner.invocations.count == 2)
  }

  @Test func resolveConflictChecksOutOrRemovesTheChosenSide() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["checkout", "--ours", "--", "a.txt"])
    runner.stub(arguments: baseFlags + ["add", "--", "a.txt"])
    runner.stub(arguments: baseFlags + ["rm", "--quiet", "--", "gone.txt"])
    let client = makeClient(runner)

    try await client.resolveConflict(path: "a.txt", using: .ours, sideHasFile: true)
    try await client.resolveConflict(path: "gone.txt", using: .theirs, sideHasFile: false)

    #expect(runner.invocations.count == 3)
  }

  @Test func rewordAndFixupSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    let oid = try #require(ObjectID(rawValue: String(repeating: "a", count: 40)))
    runner.stub(arguments: baseFlags + ["history", "reword", oid.rawValue])
    runner.stub(
      arguments: baseFlags + ["history", "fixup", "--dry-run", oid.rawValue],
      stdout: "update refs/heads/main \(String(repeating: "b", count: 40)) "
        + "\(String(repeating: "c", count: 40))\n"
    )
    let client = makeClient(runner)

    try await client.rewordCommit(oid, message: "New subject\n")
    let preview = try await client.fixupCommit(oid, dryRun: true)

    let reword = try #require(runner.invocations.first)
    #expect(reword.environment["GIT_EDITOR"] == #"cp -f "$SPOON_COMMIT_MESSAGE""#)
    #expect(reword.environment["SPOON_COMMIT_MESSAGE"] != nil)
    #expect(preview.map(\.branchName) == ["main"])
  }

  @Test func failedVersionProbeIsRetried() async {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["version"], stdout: "not a version\n")
    let client = makeClient(runner)

    #expect(await client.capabilities().version == nil)
    #expect(await client.capabilities().version == nil)

    #expect(runner.invocations.count == 2)
  }

  @Test func pushModesSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["push"])
    runner.stub(arguments: baseFlags + ["push", "--force-with-lease"])
    let client = makeClient(runner)

    try await client.push(force: false)
    try await client.push(force: true)

    #expect(runner.invocations.count == 2)
  }

  @Test func forcePushSetsUpstreamWithLeaseOnFirstPush() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["push", "--force-with-lease"],
      stderr: "fatal: use --set-upstream\n",
      exitCode: 128
    )
    runner.stub(
      arguments: baseFlags + [
        "push", "--force-with-lease", "--set-upstream", "origin", "HEAD",
      ]
    )

    try await makeClient(runner).push(force: true)

    #expect(runner.invocations.count == 2)
  }

  private let baseFlags = ["-c", "color.ui=false", "-c", "core.quotePath=false"]

  private func makeCommit(_ oid: String) -> Commit {
    Commit(
      oid: ObjectID(rawValue: oid)!,
      parents: [],
      subject: "subject",
      authorName: "Tester",
      authorEmail: "tester@example.com",
      authoredAt: Date(timeIntervalSince1970: 0),
      committedAt: Date(timeIntervalSince1970: 0)
    )
  }

  @Test func initializeSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "init", "--initial-branch", "develop", "/tmp/new-repo",
      ]
    )
    try await SystemGitClient.initialize(
      at: URL(filePath: "/tmp/new-repo"),
      initialBranch: "develop",
      git: git,
      runner: runner
    )
    #expect(runner.invocations.count == 1)
  }

  @Test func deleteBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["branch", "-d", "feature"])
    runner.stub(arguments: baseFlags + ["branch", "-D", "feature"])
    let client = makeClient(runner)
    try await client.deleteBranch(name: "feature", force: false)
    try await client.deleteBranch(name: "feature", force: true)
    #expect(runner.invocations.count == 2)
  }

  @Test func createBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "-c", "a"])
    runner.stub(arguments: baseFlags + ["switch", "-c", "b", "origin/b"])
    runner.stub(arguments: baseFlags + ["branch", "c"])
    runner.stub(arguments: baseFlags + ["branch", "d", "main"])
    let client = makeClient(runner)
    try await client.createBranch(name: "a", from: nil, switchToBranch: true)
    try await client.createBranch(name: "b", from: "origin/b", switchToBranch: true)
    try await client.createBranch(name: "c", from: nil, switchToBranch: false)
    try await client.createBranch(name: "d", from: "main", switchToBranch: false)
    #expect(runner.invocations.count == 4)
  }

  @Test func switchBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "feature"])
    try await makeClient(runner).switchBranch("feature")
    #expect(runner.invocations.count == 1)
  }

  @Test func switchToRemoteBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "--track", "origin/feature"])
    try await makeClient(runner).switchToRemoteBranch("origin/feature")
    #expect(runner.invocations.count == 1)
  }

  @Test func switchToRevisionSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "--detach", "aaaa1111"])
    try await makeClient(runner).switchToRevision(ObjectID(rawValue: "aaaa1111")!)
    #expect(runner.invocations.count == 1)
  }

  @Test func fileHistoryReflogAndResetModesSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "log", "--topo-order", "-z",
        "--format=\(GitLogParser.logFormat)",
        "--max-count=11", "HEAD", "--", "Sources/App.swift",
      ]
    )
    runner.stub(
      arguments: baseFlags + [
        "reflog", "show", "-z",
        "--format=\(GitReflogParser.format)",
        "--max-count=25", "--skip=5",
      ]
    )
    for mode in ["soft", "mixed", "hard"] {
      runner.stub(arguments: baseFlags + ["reset", "--\(mode)", "aaaa1111"])
    }
    let client = makeClient(runner)

    _ = try await client.log(
      LogQuery(path: "Sources/App.swift", maxCount: 10)
    )
    _ = try await client.reflog(maxCount: 25, skip: 5)
    let target = ObjectID(rawValue: "aaaa1111")!
    try await client.reset(to: target, mode: .soft)
    try await client.reset(to: target, mode: .mixed)
    try await client.reset(to: target, mode: .hard)

    #expect(runner.invocations.count == 5)
  }

  @Test func allReferenceLogSendsRevisionsBeforePathSeparator() async throws {
    let runner = FakeCommandRunner()
    let detached = ObjectID(rawValue: "aaaa1111")!
    runner.stub(
      arguments: baseFlags + [
        "log", "--topo-order", "-z",
        "--format=\(GitLogParser.logFormat)",
        "--max-count=6", "--skip=5", "--all", detached.rawValue, "--", "Sources/App.swift",
      ]
    )

    let page = try await makeClient(runner).log(
      LogQuery(
        path: "Sources/App.swift",
        maxCount: 5,
        skip: 5,
        allReferences: true,
        additionalRevisions: [detached]
      )
    )

    #expect(page.commits.isEmpty)
    #expect(!page.hasMore)
    #expect(runner.invocations.count == 1)
  }

  @Test func referenceLogPreservesReferenceAndAddsRevisions() async throws {
    let runner = FakeCommandRunner()
    let detached = ObjectID(rawValue: "bbbb2222")!
    runner.stub(
      arguments: baseFlags + [
        "log", "--topo-order", "-z",
        "--format=\(GitLogParser.logFormat)",
        "--max-count=11", "feature", detached.rawValue, "--",
      ]
    )

    _ = try await makeClient(runner).log(
      LogQuery(
        reference: "feature",
        maxCount: 10,
        additionalRevisions: [detached]
      )
    )

    #expect(runner.invocations.count == 1)
  }

  @Test func fileLogFollowsRenamesOnlyWithAPath() async throws {
    let runner = FakeCommandRunner()
    let prefix = [
      "log", "--topo-order", "-z", "--format=\(GitLogParser.logFormat)", "--max-count=11",
    ]
    runner.stub(arguments: baseFlags + prefix + ["--follow", "HEAD", "--", "Sources/App.swift"])
    runner.stub(arguments: baseFlags + prefix + ["HEAD", "--"])
    let client = makeClient(runner)

    _ = try await client.log(LogQuery(path: "Sources/App.swift", followRenames: true, maxCount: 10))
    _ = try await client.log(LogQuery(followRenames: true, maxCount: 10))

    #expect(runner.invocations.count == 2)
  }

  @Test(
    arguments: [
      (.message, ["--regexp-ignore-case", "--fixed-strings", "--grep=fix (ui)"]),
      (.author, ["--regexp-ignore-case", "--fixed-strings", "--author=fix (ui)"]),
      (.code, ["-Sfix (ui)"]),
    ] as [(HistorySearch.Field, [String])]
  )
  func historySearchSendsLiteralFilters(field: HistorySearch.Field, filter: [String]) async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "log", "--topo-order", "-z", "--format=\(GitLogParser.logFormat)", "--max-count=11",
      ] + filter + ["--all", "--"]
    )

    let search = HistorySearch(text: "fix (ui)", field: field)
    _ = try await makeClient(runner).log(
      LogQuery(maxCount: 10, allReferences: true, search: search)
    )

    let command = try #require(runner.invocations.first)
    #expect(command.timeout == .seconds(180))
  }

  @Test func filteredAllReferenceLogSendsIncludedAndExcludedReferences() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "log", "--topo-order", "-z",
        "--format=\(GitLogParser.logFormat)",
        "--max-count=501", "--all",
        "refs/remotes/origin/topic", "--not", "refs/heads/main", "refs/tags/v1.0", "--",
      ]
    )

    _ = try await makeClient(runner).log(
      LogQuery(
        allReferences: true,
        references: ["refs/remotes/origin/topic"],
        excludedReferences: ["refs/heads/main", "refs/tags/v1.0"]
      )
    )

    #expect(runner.invocations.count == 1)
  }

  @Test func focusedReferenceLogWalksMultipleReferences() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "log", "--topo-order", "-z",
        "--format=\(GitLogParser.logFormat)",
        "--max-count=501", "refs/heads/main", "refs/tags/v1.0", "--",
      ]
    )

    _ = try await makeClient(runner).log(
      LogQuery(references: ["refs/heads/main", "refs/tags/v1.0"])
    )

    #expect(runner.invocations.count == 1)
  }

  @Test func logQueryNextPreservesEveryCondition() {
    let detached = ObjectID(rawValue: "cccc3333")!
    let query = LogQuery(
      reference: "feature",
      path: "Sources/App.swift",
      maxCount: 25,
      skip: 50,
      allReferences: true,
      additionalRevisions: [detached]
    )

    let next = query.next()

    #expect(next.reference == query.reference)
    #expect(next.path == query.path)
    #expect(next.maxCount == query.maxCount)
    #expect(next.skip == 75)
    #expect(next.allReferences)
    #expect(next.additionalRevisions == [detached])
  }

  @Test func mergeSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["merge", "--no-edit", "feature"])
    runner.stub(arguments: baseFlags + ["merge", "--no-edit", "origin/feature"])
    runner.stub(arguments: baseFlags + ["merge", "--squash", "feature"])
    runner.stub(arguments: baseFlags + ["merge", "--ff-only", "feature"])
    runner.stub(
      arguments: baseFlags + [
        "merge", "--no-ff", "--no-edit",
        "--strategy=ort", "--strategy-option=theirs", "feature",
      ]
    )
    let client = makeClient(runner)
    try await client.merge(branch: "feature", options: .standard)
    try await client.merge(branch: "origin/feature", options: .standard)
    try await client.merge(
      branch: "feature",
      options: MergeOptions(commitMode: .squash)
    )
    try await client.merge(
      branch: "feature",
      options: MergeOptions(commitMode: .fastForwardOnly)
    )
    try await client.merge(
      branch: "feature",
      options: MergeOptions(
        commitMode: .createMergeCommit,
        strategy: .ort,
        conflictPreference: .theirs
      )
    )
    #expect(runner.invocations.count == 5)
  }

  @Test func mergeSequencerControlsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["merge", "--continue"])
    runner.stub(arguments: baseFlags + ["merge", "--abort"])
    let client = makeClient(runner)
    try await client.continueSequencer(.merge)
    try await client.abortSequencer(.merge)
    #expect(runner.invocations.count == 2)
  }

  @Test func tagOperationsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "for-each-ref", "refs/tags",
        "--sort=-creatordate",
        "--format=\(GitTagParser.tagFormat)",
      ],
      stdout: "v1\u{0}aaaa1111\u{0}\u{0}1720000000\n"
    )
    runner.stub(arguments: baseFlags + ["tag", "v1"])
    runner.stub(arguments: baseFlags + ["tag", "-a", "-m", "release", "v2", "aaaa1111"])
    runner.stub(arguments: baseFlags + ["tag", "-d", "v1"])

    let client = makeClient(runner)
    let tags = try await client.tags()
    #expect(tags.map(\.name) == ["v1"])
    try await client.createTag(name: "v1", at: nil, message: nil)
    try await client.createTag(
      name: "v2", at: ObjectID(rawValue: "aaaa1111"), message: "release")
    try await client.deleteTag(name: "v1")
    #expect(runner.invocations.count == 4)
  }

  @Test func remoteTagOperationsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["push", "origin", "refs/tags/v1"])
    runner.stub(arguments: baseFlags + ["push", "upstream", "--tags"])
    runner.stub(
      arguments: baseFlags + [
        "push", "origin", "--delete", "refs/tags/v1",
      ]
    )
    let client = makeClient(runner)

    try await client.pushTag(name: "v1", to: "origin")
    try await client.pushAllTags(to: "upstream")
    try await client.deleteRemoteTag(name: "v1", from: "origin")

    #expect(runner.invocations.count == 3)
  }

  @Test func renameBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["branch", "-m", "old-name", "new-name"])
    runner.stub(
      arguments: baseFlags + [
        "branch", "--set-upstream-to", "origin/new-name", "new-name",
      ]
    )
    let client = makeClient(runner)
    try await client.renameBranch(from: "old-name", to: "new-name")
    try await client.setUpstream(of: "new-name", to: "origin/new-name")
    #expect(runner.invocations.count == 2)
  }

  @Test func remoteBranchMutationsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "push", "origin",
        "refs/remotes/origin/feature/old:refs/heads/feature/new",
      ]
    )
    runner.stub(arguments: baseFlags + ["push", "origin", "--delete", "feature/old"])
    runner.stub(arguments: baseFlags + ["push", "upstream", "--delete", "obsolete"])
    let client = makeClient(runner)

    try await client.renameRemoteBranch(
      remoteName: "origin",
      from: "feature/old",
      to: "feature/new"
    )
    try await client.deleteRemoteBranch(name: "obsolete", from: "upstream")

    #expect(runner.invocations.count == 3)
  }

  @Test func publishBranchPushesNamedBranchAndSetsUpstream() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "push", "--set-upstream", "origin",
        "refs/heads/feature/new:refs/heads/feature/new",
      ]
    )

    try await makeClient(runner).publishBranch("feature/new", to: "origin")

    #expect(runner.invocations.count == 1)
  }

  @Test func deletingMissingRemoteBranchIsAlreadySuccessful() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["push", "origin", "--delete", "already-gone"],
      stderr: "remote: error: remote ref does not exist\n",
      exitCode: 1
    )

    try await makeClient(runner).deleteRemoteBranch(name: "already-gone", from: "origin")
    #expect(runner.invocations.count == 1)
  }

  @Test func worktreeOperationsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["worktree", "list", "--porcelain"],
      stdout: "worktree /tmp/fake-repo\nHEAD 1234abcd\nbranch refs/heads/main\n\n"
    )
    runner.stub(arguments: baseFlags + ["worktree", "add", "/tmp/wt", "feature"])
    runner.stub(
      arguments: baseFlags + [
        "worktree", "add", "--track", "-b", "topic", "/tmp/remote-wt", "origin/topic",
      ]
    )
    runner.stub(arguments: baseFlags + ["worktree", "remove", "/tmp/wt"])
    runner.stub(arguments: baseFlags + ["worktree", "remove", "--force", "/tmp/wt"])

    let client = makeClient(runner)
    let worktrees = try await client.worktrees()
    #expect(worktrees.map(\.branch) == ["main"])
    try await client.addWorktree(path: URL(filePath: "/tmp/wt"), branch: "feature")
    try await client.addWorktree(
      path: URL(filePath: "/tmp/remote-wt"),
      remoteBranch: "origin/topic",
      localBranch: "topic"
    )
    try await client.removeWorktree(path: URL(filePath: "/tmp/wt"), force: false)
    try await client.removeWorktree(path: URL(filePath: "/tmp/wt"), force: true)
    #expect(runner.invocations.count == 5)
  }

  @Test func sparseCheckoutOperationsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["config", "--bool", "core.sparseCheckout"],
      stdout: "true\n"
    )
    runner.stub(
      arguments: baseFlags + ["sparse-checkout", "list"],
      stdout: "Sources\nTests\n"
    )
    runner.stub(
      arguments: baseFlags + [
        "sparse-checkout", "set", "--cone", "--", "Sources", "Tests",
      ]
    )
    runner.stub(arguments: baseFlags + ["sparse-checkout", "disable"])
    let client = makeClient(runner)

    #expect(try await client.sparseCheckoutPaths() == ["Sources", "Tests"])
    try await client.setSparseCheckout(paths: ["Sources", "Tests"])
    try await client.disableSparseCheckout()

    #expect(runner.invocations.count == 4)
  }

  @Test func sparseCheckoutRejectsEmptyPathsWithoutRunningGit() async {
    let runner = FakeCommandRunner()
    let client = makeClient(runner)

    await #expect(throws: SparseCheckoutError.emptyPaths) {
      try await client.setSparseCheckout(paths: ["", "  "])
    }
    #expect(runner.invocations.isEmpty)
  }

  @Test func cherryPickAndRevertSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["cherry-pick", "aaaa1111"])
    runner.stub(arguments: baseFlags + ["revert", "--no-edit", "bbbb2222"])
    let client = makeClient(runner)
    try await client.cherryPick(ObjectID(rawValue: "aaaa1111")!)
    try await client.revert(ObjectID(rawValue: "bbbb2222")!)
    #expect(runner.invocations.count == 2)
    // No editor override: git must not open one for these non-interactive forms.
    #expect(runner.invocations.allSatisfy { $0.environment["GIT_EDITOR"] == nil })
  }

  @Test func interactiveRebaseSendsArgvAndEnvironment() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["rebase", "--interactive", "beef0000"])
    let plan = RebasePlan(
      steps: [RebaseStep(action: .pick, commit: makeCommit("aaaa1111"))],
      baseOID: ObjectID(rawValue: "beef0000")
    )
    try await makeClient(runner).interactiveRebase(plan)

    let command = try #require(runner.invocations.first)
    #expect(command.environment["GIT_SEQUENCE_EDITOR"] == #"cp -f "$SPOON_REBASE_TODO""#)
    #expect(command.environment["GIT_EDITOR"] == "true")
    let todoPath = try #require(command.environment["SPOON_REBASE_TODO"])
    // The temp todo file is cleaned up after the run.
    #expect(!FileManager.default.fileExists(atPath: todoPath))
    // Base env survives the merge.
    #expect(command.environment["GIT_TERMINAL_PROMPT"] == "0")
  }

  @Test func rootRebaseUsesRootFlag() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["rebase", "--interactive", "--root"])
    let plan = RebasePlan(
      steps: [RebaseStep(action: .pick, commit: makeCommit("aaaa1111"))],
      baseOID: nil
    )
    try await makeClient(runner).interactiveRebase(plan)
    #expect(runner.invocations.count == 1)
  }

  @Test func sequencerControlsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    for subcommand in ["rebase", "cherry-pick", "revert"] {
      for flag in ["--continue", "--skip", "--abort"] {
        runner.stub(arguments: baseFlags + [subcommand, flag])
      }
    }
    let client = makeClient(runner)
    for kind in [SequencerState.Kind.rebase, .cherryPick, .revert] {
      try await client.continueSequencer(kind)
      try await client.skipSequencer(kind)
      try await client.abortSequencer(kind)
    }
    #expect(runner.invocations.count == 9)
    for command in runner.invocations {
      let isAbort = command.arguments.contains("--abort")
      #expect(command.environment["GIT_EDITOR"] == (isAbort ? nil : "true"))
    }
  }

  @Test func sequencerStateIsNilWhenNoStateFilesExist() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "rev-parse",
        "--git-path", "rebase-merge",
        "--git-path", "rebase-apply",
        "--git-path", "CHERRY_PICK_HEAD",
        "--git-path", "REVERT_HEAD",
        "--git-path", "MERGE_HEAD",
      ],
      stdout:
        ".git/rebase-merge\n.git/rebase-apply\n.git/CHERRY_PICK_HEAD\n.git/REVERT_HEAD\n.git/MERGE_HEAD\n"
    )
    let state = try await makeClient(runner).sequencerState()
    #expect(state == nil)
  }

  @Test func stashDiffsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "stash", "show", "--include-untracked", "--patch", "--find-renames", "stash@{1}",
      ],
      stdout: """
        diff --git a/file.txt b/file.txt
        index 0000000..1111111 100644
        --- a/file.txt
        +++ b/file.txt
        @@ -1 +1 @@
        -old
        +new

        """
    )
    let diffs = try await makeClient(runner).stashDiffs(
      Stash(index: 1, target: ObjectID(rawValue: "aaaa1111")!, message: "wip")
    )
    #expect(diffs.map(\.path) == ["file.txt"])
  }

  @Test func stashesSendExactArgvAndParseTargets() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "stash", "list", "-z", "--format=%H%x1f%P%x1f%gd%x1f%gs",
      ],
      stdout:
        "aaaa1111\u{1f}11111111 bbbb2222 cccc3333\u{1f}stash@{0}\u{1f}On main: useful\u{0}"
    )

    let stashes = try await makeClient(runner).stashes()

    #expect(stashes.count == 1)
    #expect(stashes[0].index == 0)
    #expect(stashes[0].target.rawValue == "aaaa1111")
    #expect(stashes[0].helperCommitOIDs.map(\.rawValue) == ["bbbb2222", "cccc3333"])
    #expect(stashes[0].message == "On main: useful")
  }

  @Test func parsesRemoteListing() {
    let remotes = SystemGitClient.parseRemotes(
      """
      origin\tgit@github.com:owner/repo.git (fetch)
      origin\tgit@github.com:owner/repo.git (push)
      fork\thttps://github.com/me/repo.git (fetch)
      fork\thttps://github.com/me/push-elsewhere.git (push)
      """
    )
    #expect(remotes.count == 2)
    #expect(remotes[0].name == "origin")
    #expect(remotes[0].fetchURL == "git@github.com:owner/repo.git")
    #expect(remotes[0].pushURL == nil)
    #expect(remotes[1].name == "fork")
    #expect(remotes[1].pushURL == "https://github.com/me/push-elsewhere.git")
  }
}
