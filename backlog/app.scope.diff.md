# Swag Scope Diff Viewer Backlog

This backlog covers the planned read-only viewer for unified diffs and Git patches, and
comparison of two explicitly selected local text sources.

### app.scope.diff.001 — Diff and patch files read as plain text

- Evidence: unified diffs are among the most frequently opened developer files and are the format
  where flat text costs the most. The current Text view cannot distinguish file headers, metadata,
  hunks, additions, removals, context, no-newline markers, binary notices, renames, modes, or
  malformed ranges. There is no inline/side-by-side layout, collapsed unchanged region,
  previous/next-change navigation or accessible change representation.
- Next: parse unified and Git patch syntax into immutable file/hunk/line ranges, beginning with a
  themed unified view and a file/hunk outline before adding a synchronized side-by-side projection.
- Done when: file and hunk navigation, inline and side-by-side layouts, intraline differences,
  whitespace visibility, collapsed context, exact source copying, malformed-hunk diagnostics, and
  keyboard/screen-reader change navigation work without offering stage, revert, or patch apply.

### app.scope.diff.002 — Two local text files cannot be compared

- Evidence: Swag Scope can read a patch that another tool produced, but it cannot compare the open
  text with another local file or clipboard snapshot.
- Next: reuse the immutable diff presentation from app.scope.diff.001 with a cancellable,
  memory-budgeted line matcher and explicit left/right source identities.
- Done when: the reader can select a second local text file or clipboard snapshot, choose
  line-ending and whitespace comparison policy, navigate exact and moved changes, copy from either
  side, and cancel or degrade a huge comparison without modifying either source.
- Related: app.scope.diff.001, app.scope.viewers.004
