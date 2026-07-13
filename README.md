# Spoon

An AI-first git client for macOS, built with SwiftUI for macOS 26 or later.

![Spoon](docs/screenshot.png)

## Features

- **Changes** — files shown as a directory tree (collapsible, single-child
  chains folded). Stage / unstage whole files, hunks, or individually
  selected lines — in both directions (line-level unstage on staged diffs).
  Multi-select with ⌘/⇧, double-click or press Return to move files, drag &
  drop between areas, discard selected lines, right-click to open a file or
  reveal it in Finder.
- **History** — commit graph with infinite scroll; commit details show the
  full patch. File history and reflog inspection are available from contextual
  menus and the sidebar.
- **Interactive rebase** — pick / squash / drop / edit with drag-to-reorder,
  from a commit's context menu; plus cherry-pick and revert. Conflicts and
  edit stops show a banner with Continue / Skip / Abort.
- **Branches** — create (from HEAD or any branch), delete, rename, and check
  out branches (or any commit, detached); merge or squash-merge a branch
  into the current one; check out a remote branch as a local tracking
  branch; link a branch to its own worktree (add / open in a new window /
  remove).
- **Tags** — list in the sidebar, tag any commit (lightweight or annotated),
  push to remotes, and delete locally or remotely.
- **Stashes** — save (including untracked files), browse a stash's diff,
  apply, pop, or drop it.
- **Clone** — clone over https / ssh from the Welcome screen with live
  progress. Existing folders can also be initialized as repositories.
- **Remotes and storage** — add, edit, and remove remotes; fetch partial-clone
  objects when supported; configure cone-mode sparse checkout.
- **Pull requests** — branches display their open GitHub PR with review and
  CI status; a PR list and detail view come from the GitHub GraphQL API.
- **AI** — generate commit messages and review branches with Claude Code or
  Codex, running the CLIs you already have installed.
- **Shortcuts** — App Intents for “Open Repository” and “Stash Changes”.
- Auto-refresh via FSEvents, repository-titled windows and tabs.

## Spoon vs Fork

How Spoon compares to [Fork](https://git-fork.com) (“—” means not
available, to our knowledge).

| Feature | Fork | Spoon |
|---|:-:|:-:|
| Fetch / pull / push | ✅ | ✅ |
| Commit & amend | ✅ | ✅ |
| Stage / unstage line-by-line | ✅ | ✅ |
| Discard selected lines | ✅ | ✅ |
| Commit graph / history | ✅ | ✅ |
| Clone / add / recent repositories | ✅ | ✅ |
| Branches: create / delete | ✅ | ✅ |
| Branch rename / branch from branch | ✅ | ✅ |
| Checkout branch or revision | ✅ | ✅ |
| Tags | ✅ | ✅ |
| Worktrees linked to branches | ✅ | ✅ |
| Interactive rebase | ✅ | ✅ |
| Cherry-pick / revert | ✅ | ✅ |
| Merge | ✅ | ✅ |
| Merge conflict resolving | ✅ built-in resolver | partial (conflict banner + mark resolved) |
| Stashes | ✅ | ✅ (incl. diff browsing) |
| Submodules | ✅ | — |
| Git-flow | ✅ | — |
| Git LFS | ✅ | — |
| GPG signing | ✅ | — |
| Blame / file history | ✅ | partial (file history, no blame) |
| Reflog | ✅ | ✅ |
| Image diffs / side-by-side diff | ✅ | — |
| GitHub integration | Notifications | PR badges on branches, PR list & details (CI + reviews) |
| AI commit messages (Claude Code / Codex) | ✅ | ✅ |
| AI branch review (Claude Code / Codex) | ✅ | ✅ |
| Shortcuts / App Intents | — | ✅ |

## Git features not in Spoon (yet)

Spoon shells out to your system `git` and covers everyday client workflows. The
items below exist in **modern Git** (including recent 2.4x–2.55 releases) but
are **not exposed** in Spoon’s UI or `GitClient` API today.

### History & inspection

- **Blame** — `git blame` / annotate lines in a file
- **Bisect** — binary search for the commit that introduced a bug
- **Range diff** — `git range-diff`, including `--remerge-diff` (2.48+)

### Commits & history editing

- **`git history reword` / `git history split`** (2.54+, experimental) — simpler
  history edits without a full interactive rebase
- **`git replay`** (experimental) — replay commits onto a new base without
  touching the working tree

### Merge, push & conflicts

- **Built-in 3-way merge resolver** — Spoon detects conflicts and can mark files
  resolved by staging; there is no inline merge editor or `git mergetool` UI

### Signing & integrity

- **GPG / SSH commit signing** — `-S`, `commit.gpgsign`, signed-tag workflows
- **Signed-tag verification** — beyond listing tag names

### Large repos & storage

- **Git LFS** — `git lfs` track/fetch/push
- **Submodules** — init/update/status in nested repos
- **Reftable backend** (2.45+) — `init --ref-format=reftable`, `refs migrate`
- **`git maintenance`** — configure geometric repack and other maintenance tasks
- **`git repo info` / `git repo structure`** (2.52+) — repository size and layout
  diagnostics

### Diffs & workflows

- **Image diffs** and **side-by-side diff** views
- **Git-flow** — branch naming / release/hotfix helpers
- **Hooks editor** — hooks may run when you commit; Spoon does not manage them
  (Git 2.54+ also supports hooks defined in config)
- **Git config UI** — no in-app editor for repo/user gitconfig (tool-path
  overrides exist internally but are not wired to Settings yet)

## Requirements

- macOS 26 or later
- `git` (Xcode Command Line Tools are enough)
- To build from source: Xcode 26.3 or later with Swift 6.3
- Optional, for the matching features:
  - [`gh`](https://cli.github.com) — GitHub authentication for PR sync
  - [`claude`](https://claude.com/claude-code) and/or `codex` — AI commit
    messages and reviews

## Building

Open `Spoon.xcodeproj` with Xcode 26.3 or later and run the **Spoon** scheme.

The package checks used by CI can also be run directly:

```sh
cd SpoonKit
swift build --target SpoonUI
swift test --test-product SpoonCoreTests
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow,
[docs/architecture.md](docs/architecture.md) for the code structure, and
[docs/testing.md](docs/testing.md) for test categories and manual smoke checks.

## License

[Apache License 2.0](LICENSE)
