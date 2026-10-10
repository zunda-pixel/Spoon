# SwiftUI layout and update boundaries

Action groups in the commit composer, conflict headers, bisect/sequencer banners,
stash header, and software update window use `AdaptiveActionsLayout` with
`WrappingLayout`. Both groups share a row when their ideal widths fit; otherwise
actions move below and individual controls can wrap further. A single subtree
survives resizing, instead of switching between copies in `ViewThatFits`.
`WrappingLayout` caches ideal measurements using SwiftUI's layout cache lifecycle.
No measured control sizes live in `@State`.

Diffs need a minimum viewport width while retaining natural code widths for
horizontal scrolling. `DiffScrollView` observes only width with
`onGeometryChange` and owns that state locally. A fixed container-relative width
would constrain long lines; observing full frames would also react to irrelevant
position/height changes.

The remaining `fixedSize` modifiers are deliberate:

- Diff code ignores horizontal proposals so complete lines remain scrollable.
- Wrapped explanations, conflict text, blame text, and release notes request
  ideal vertical height to keep text visible under constrained proposals.

Pickers use layout priority instead of refusing all size proposals. Long branch
or reference names can yield space to the surrounding controls.

Word matching is cached per hunk content and highlight setting. A SwiftUI task
calls an `@concurrent` calculation, then applies its result on the main actor only
if the task is still current. Rendering also checks the input attached to the
result, so stale highlights are not drawn during a content change. Selection and
expansion do not restart matching.

## Verification

`WrappingLayoutTests` covers exact-width boundaries, row heights, empty/zero-width
input, and renders the adaptive layout at wide and narrow proposals, including
actions that need multiple rows. Existing core and UI tests cover repository and
selection behavior.

Manual interaction checks still matter: resize repository columns with menus open,
use long branch names, select diff lines while toggling word highlighting, and
verify pinned headers and horizontal scrolling with both short and long patches.
CPU/frame-time improvements require an Instruments trace; these changes alone do
not establish a measured speedup.
