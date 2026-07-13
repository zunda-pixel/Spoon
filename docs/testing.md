# Testing

## Automated test categories

`SpoonCoreTests` uses Swift Testing and is organized by responsibility:

- **Parsing and pure domain logic** — status, diff, log, ref, reflog, tag, and
  worktree parsers; file trees; diff patch construction; clone and rebase
  options; commit graph layout.
- **Command construction** — `SystemGitClientTests` and clone tests verify
  arguments, environment, stdin, timeouts, and error handling with
  `FakeCommandRunner`.
- **Repository integration** — `LiveGitTests`, `LiveRepositoryTests`, and
  `LiveSequencerTests` create temporary repositories through
  `LiveRepoFixture` and exercise the installed git executable.
- **Session behavior** — `RepositoryModelTests` verifies snapshot application,
  mutation refreshes, stores, and observable state transitions with fakes.
- **Services** — GitHub, AI provider, process runner, and repository watcher
  tests cover their isolated boundaries.

`SpoonIntentTests` covers App Intent parameter and model behavior separately.
Live AI and live intent tests require their external tools or environment and
are not part of the default core CI command.

## Required local and CI checks

Run the same package checks as `.github/workflows/ci.yml`:

```sh
cd SpoonKit
swift build --target SpoonUI
swift test --test-product SpoonCoreTests
cd ..
git diff --check
```

`Package.swift` enables strict memory safety, current concurrency features, and
treats all compiler warnings as errors. This compiler pass is the required
lint. When `swift-format` is available, run its lint mode as an additional
style check:

```sh
swift format lint --recursive Spoon SpoonKit/Sources SpoonKit/Tests
```

Tests that use a real repository must create it under a temporary directory,
set deterministic local git identity/configuration, and clean it up. They must
not read or modify the contributor's working repository.

## Manual smoke test

Automated tests do not validate macOS interaction, VoiceOver output, or every
external CLI. Before a release, exercise a disposable repository:

1. Open, initialize, and clone repositories; confirm recent items and
   repository-titled windows.
2. Stage and unstage files, hunks, and lines with pointer, Return, context
   menus, and drag and drop. Verify discard confirmations.
3. Commit and amend; fetch, pull, push, and force-push-with-lease confirmation.
4. Browse history, file history, reflog, commit details, branches, tags,
   stashes, remotes, sparse checkout, and linked worktrees.
5. Start a merge or interactive rebase that pauses. Verify conflict state and
   Continue, Skip, and Abort from both the banner and Repository menu.
6. Verify Repository and View menu shortcuts in more than one repository
   window. Disabled items must follow the focused window and busy/sequencer
   state.
7. With VoiceOver enabled, traverse the toolbar, Changes tree, diff headers and
   selectable lines, commit graph, sequencer banner, and sidebar. Confirm
   labels, status values, grouping, and reading order; no state may rely on
   color alone.
8. Check light and dark appearances, Increased Contrast, Reduce Transparency,
   and keyboard-only navigation.
9. If configured, sync GitHub PRs and run Claude Code/Codex commit generation
   and branch review. Confirm failures do not block local git workflows.
