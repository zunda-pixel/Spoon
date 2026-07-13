import Foundation
import Synchronization
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
      stdout: "*\u{0}main\u{0}4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331\u{0}subject\u{0}\u{0}\u{0}1720000000\n"
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
        "remote", "remove", "origin",
      ]
    )
    let client = makeClient(runner)
    try await client.addRemote(name: "origin", url: "https://github.com/o/r.git")
    try await client.removeRemote(name: "origin")
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

  @Test func cloneSendsExactArgvAndStreamsProgress() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "clone", "--progress", "https://example.com/repo.git", "/tmp/clone-dest",
      ],
      stderr: "Cloning into 'clone-dest'...\nReceiving objects:  50%\rReceiving objects: 100%, done.\n"
    )
    let lines = Mutex<[String]>([])
    try await SystemGitClient.clone(
      from: "https://example.com/repo.git",
      to: URL(filePath: "/tmp/clone-dest"),
      git: git,
      runner: runner
    ) { line in
      lines.withLock { $0.append(line) }
    }
    #expect(runner.invocations.count == 1)
    #expect(lines.withLock { $0.last } == "Receiving objects: 100%, done.")
  }

  @Test func cloneFailureBecomesCommandError() async {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "clone", "--progress", "https://example.com/missing.git", "/tmp/clone-missing",
      ],
      stderr: "fatal: repository not found\n",
      exitCode: 128
    )
    await #expect(throws: CommandError.self) {
      try await SystemGitClient.clone(
        from: "https://example.com/missing.git",
        to: URL(filePath: "/tmp/clone-missing"),
        git: git,
        runner: runner
      ) { _ in }
    }
  }

  @Test func cloneWithOptionsSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "clone", "--progress",
        "--filter=blob:none",
        "--depth=10",
        "--single-branch",
        "--branch", "main",
        "https://example.com/repo.git", "/tmp/clone-dest",
      ]
    )
    let options = CloneOptions(
      filterBlobNone: true,
      depth: 10,
      singleBranch: true,
      branch: "main"
    )
    try await SystemGitClient.clone(
      from: "https://example.com/repo.git",
      to: URL(filePath: "/tmp/clone-dest"),
      options: options,
      git: git,
      runner: runner
    ) { _ in }
    #expect(runner.invocations.count == 1)
  }

  @Test func createBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "-c", "a"])
    runner.stub(arguments: baseFlags + ["switch", "-c", "b", "origin/b"])
    runner.stub(arguments: baseFlags + ["branch", "c"])
    runner.stub(arguments: baseFlags + ["branch", "d", "main"])
    let client = makeClient(runner)
    try await client.createBranch(name: "a", from: nil, checkout: true)
    try await client.createBranch(name: "b", from: "origin/b", checkout: true)
    try await client.createBranch(name: "c", from: nil, checkout: false)
    try await client.createBranch(name: "d", from: "main", checkout: false)
    #expect(runner.invocations.count == 4)
  }

  @Test func checkoutRemoteBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "--track", "origin/feature"])
    try await makeClient(runner).checkoutRemoteBranch("origin/feature")
    #expect(runner.invocations.count == 1)
  }

  @Test func checkoutRevisionSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["switch", "--detach", "aaaa1111"])
    try await makeClient(runner).checkoutRevision(ObjectID(rawValue: "aaaa1111")!)
    #expect(runner.invocations.count == 1)
  }

  @Test func mergeSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["merge", "--no-edit", "feature"])
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
    #expect(runner.invocations.count == 4)
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

  @Test func renameBranchSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(arguments: baseFlags + ["branch", "-m", "old-name", "new-name"])
    try await makeClient(runner).renameBranch(from: "old-name", to: "new-name")
    #expect(runner.invocations.count == 1)
  }

  @Test func worktreeOperationsSendExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + ["worktree", "list", "--porcelain"],
      stdout: "worktree /tmp/fake-repo\nHEAD 1234abcd\nbranch refs/heads/main\n\n"
    )
    runner.stub(arguments: baseFlags + ["worktree", "add", "/tmp/wt", "feature"])
    runner.stub(arguments: baseFlags + ["worktree", "remove", "/tmp/wt"])
    runner.stub(arguments: baseFlags + ["worktree", "remove", "--force", "/tmp/wt"])

    let client = makeClient(runner)
    let worktrees = try await client.worktrees()
    #expect(worktrees.map(\.branch) == ["main"])
    try await client.addWorktree(path: URL(filePath: "/tmp/wt"), branch: "feature")
    try await client.removeWorktree(path: URL(filePath: "/tmp/wt"), force: false)
    try await client.removeWorktree(path: URL(filePath: "/tmp/wt"), force: true)
    #expect(runner.invocations.count == 4)
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
    let diffs = try await makeClient(runner).stashDiffs(Stash(index: 1, message: "wip"))
    #expect(diffs.map(\.path) == ["file.txt"])
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
