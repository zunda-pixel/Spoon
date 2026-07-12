# Spoon

An AI-first git client for macOS, built with SwiftUI for macOS 27 (Golden Gate).

![Spoon](docs/screenshot.png)

## Features

- **Changes** — files shown as a directory tree (collapsible, single-child
  chains folded). Stage / unstage whole files, hunks, or individually
  selected lines — in both directions (line-level unstage on staged diffs).
  Multi-select with ⌘/⇧, double-click or press Return to move files, drag &
  drop between areas, discard selected lines, right-click to open a file or
  reveal it in Finder.
- **History** — commit graph with infinite scroll; commit details show the
  full patch with selectable, copyable lines.
- **Interactive rebase** — pick / squash / drop / edit with drag-to-reorder,
  from a commit's context menu; plus cherry-pick and revert. Conflicts and
  edit stops show a banner with Continue / Skip / Abort.
- **Branches** — create (from HEAD or any branch), delete, rename, and check
  out branches (or any commit, detached); merge or squash-merge a branch
  into the current one; check out a remote branch as a local tracking
  branch; link a branch to its own worktree (add / open in a new window /
  remove).
- **Tags** — list in the sidebar, tag any commit (lightweight or annotated),
  delete.
- **Stashes** — save (including untracked files), browse a stash's diff,
  apply, pop, or drop it.
- **Clone** — clone over https / ssh from the Welcome screen with live
  progress.
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
| Discard selected lines | — | ✅ |
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
| Blame / file history | ✅ | — |
| Reflog | ✅ | — |
| Image diffs / side-by-side diff | ✅ | — |
| GitHub integration | Notifications | PR badges on branches, PR list & details (CI + reviews) |
| AI commit messages (Claude Code / Codex) | ✅ | ✅ |
| AI branch review (Claude Code / Codex) | ✅ | ✅ |
| Shortcuts / App Intents | — | ✅ |

## Requirements

- macOS 27 (Golden Gate) or later
- `git` (Xcode Command Line Tools are enough)
- Optional, for the matching features:
  - [`gh`](https://cli.github.com) — GitHub authentication for PR sync
  - [`claude`](https://claude.com/claude-code) and/or `codex` — AI commit
    messages and reviews

## Building

Open `Spoon.xcodeproj` with Xcode 27 and run the **Spoon** scheme.

## License

[Apache License 2.0](LICENSE)
