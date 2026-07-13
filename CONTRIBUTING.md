# Contributing to Spoon

## Prerequisites

- macOS 26 or later
- Xcode 26.3 or later with Swift 6.3
- System `git`
- Optional `gh`, `claude`, and `codex` CLIs for their integrations

## Development workflow

1. Create a focused branch and keep changes scoped to one concern.
2. Open `Spoon.xcodeproj` for app work. Package code lives in `SpoonKit`.
3. Preserve the separation between `SpoonCore` domain/process code and
   `SpoonUI` presentation code.
4. Add deterministic tests for parsers, command construction, model state,
   and bug fixes. Use live tests only when behavior requires a real repository.
5. Run the checks below before opening a pull request.

```sh
cd SpoonKit
swift build --target SpoonUI
swift test --test-product SpoonCoreTests
cd ..
git diff --check
```

The package treats Swift compiler warnings as errors. If `swift-format` is
installed, lint changed Swift files without rewriting unrelated code:

```sh
swift format lint --recursive Spoon SpoonKit/Sources SpoonKit/Tests
```

## Code and UI expectations

- Use Swift concurrency and isolation explicitly; `RepositoryModel` and UI
  state are main-actor isolated, while `SystemGitClient` serializes git access.
- Keep public API additions intentional. Prefer internal access for app-only
  implementation details and document public domain contracts.
- Use semantic SwiftUI fonts, colors, and materials. Do not hardcode UI colors
  or text sizes.
- Every icon-only action needs a useful VoiceOver label and hint. State must not
  be communicated by color alone, and pointer actions need a menu or keyboard
  equivalent.
- Use destructive roles and confirmation where an operation cannot be undone.
- Do not include debug logging, generated build products, credentials, or
  unresolved TODOs in a pull request.

See [docs/architecture.md](docs/architecture.md) and
[docs/testing.md](docs/testing.md) for more detail.
