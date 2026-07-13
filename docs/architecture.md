# Architecture

Spoon is a macOS SwiftUI app backed by the `SpoonKit` Swift package. The package
separates repository behavior (`SpoonCore`), App Intents (`SpoonIntent`), and
presentation (`SpoonUI`). The app target owns scene and application lifecycle.

## Git domain and process boundary

`GitClient.swift` divides repository behavior into focused, `Sendable`
protocols:

- `GitWorkingTreeClient`
- `GitHistoryClient`
- `GitBranchClient`
- `GitRemoteClient`
- `GitTagClient`
- `GitWorktreeClient`
- `GitSparseCheckoutClient`
- `GitSequencerClient`
- `GitReviewClient`
- `GitStashClient`

`GitClient` remains the aggregate protocol used by the current model, services,
and test doubles. `GitRepositoryLifecycle` handles discovery, initialization,
and clone operations that do not require an already-open repository client.

`SystemGitClient` is one actor per repository. It owns the git executable,
repository root, and command runner; actor isolation serializes commands that
may contend for git's index lock. Shared execution helpers stay in
`SystemGitClient.swift`, while domain conformances are split into
`SystemGitClient+WorkingTree.swift`, `+History`, `+Branch`, `+Remote`, `+Tag`,
`+Worktree`, `+SparseCheckout`, `+Sequencer`, `+Review`, and `+Stash`.
Lifecycle convenience APIs are in `+Lifecycle`.

Parsers convert stable machine-oriented git output into domain models. Command
construction and parsing remain outside SwiftUI so they can be tested without
launching the app.

## Repository state and stores

`RepositoryModel` is the main-actor facade for one repository window. Its
extensions group refresh, history, diffs, mutations, sequencer, PR, AI, and
watching behavior instead of growing one monolithic type.

`RepositoryGitSnapshot` loads independent git reads concurrently, then applies
the complete snapshot atomically. A failed read does not leave the model with a
partially updated combination of status, branches, remotes, stashes, tags,
worktrees, and sequencer state. Applying a snapshot also rebuilds the cached
Changes directory trees.

Longer-lived feature state is delegated to focused stores:

- `HistoryStore` owns history pagination, graph rows, and history errors.
- `PullRequestStore` owns GitHub synchronization, cached snapshots, and
  branch-to-PR linking. GitHub failures do not replace local git state.
- `AIStore` owns provider registration, activity, generated review output, and
  coding-agent errors.

`RepositoryModel` exposes the UI-facing values and operations while preserving
store ownership. `RepoWatcher` feeds filesystem changes back into `refresh`;
self-originated events are suppressed while a mutation or refresh is active.

## Navigation and presentation

Each repository window creates one `RepositoryNavigationState`. It owns sidebar
selection, selected files/revisions/PRs, the active sheet, and window-level
confirmations. `RepositorySplitView` uses a three-column
`NavigationSplitView`:

1. `RepoSidebarView` selects workspace and repository scopes.
2. `RepositoryContentColumn` displays Changes, history, reflog, PRs, remotes,
   or stashes.
3. `RepositoryDetailColumn` displays a diff, commit, PR, or selection
   placeholder.

`RepositorySheetHost` is the single mapping from navigation sheet state to
sheet content. `RepositoryToolbar` contains frequent actions. `SpoonCommands`
routes menu commands to the focused repository model and navigation state, so
menu enabled state follows the active window. The standard View menu contains
section navigation; repository mutations live in the Repository menu.

The sequencer banner is window-wide and remains visible while rebase,
cherry-pick, revert, or merge is paused. Its actions are duplicated in the
Repository menu for keyboard and VoiceOver access.

## Dependency direction

`SpoonUI` depends on `SpoonCore`; `SpoonCore` does not import `SpoonUI`.
Infrastructure implementations conform to domain protocols, and tests inject
fake command runners or fake git clients. App-only navigation and presentation
types remain internal unless another target genuinely needs them.
