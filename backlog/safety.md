# Safety Backlog

The borrow, lifetime, and sanity analyses: what they judge, what they miss, and what they refuse
to judge at all. The borrow rules are the language and are always on; the analyses that prove a
runtime fault are tooling under `#[Swag.Sanity]`. The reference states the line
([013_004_borrowing.swg](../bin/reference/modules/language/src/013_004_borrowing.swg)).

[README.md](README.md) defines the shared backlog conventions.

## Borrow invalidation

### B-019 — A pointer read out of a container is judged to view the container

- Area: compiler/sema, `SemaEscape`
- Found while: making a written `#[Inline]` honored across files (2026-08-28), which lets the
  analysis see into `Core.Array.opIndexPtr` for the first time.
- Evidence: `pixel/src/poly/clipper.swg` no longer compiles. `getLastOutPt` and `addOutPt` read
  `.polyOuts[i]` out of an `Array'#null *OutRec`, dereference the pointer they find there, and
  return an `OutPt` node that `Memory.new` allocated. The analysis records that return as a view
  of `me.polyOuts`, so a later `.addOutPt` or `.intersectEdges` that grows the array reports
  eleven `sanity_err_borrow_invalidated`. Growing an array of pointers moves the pointers, never
  the nodes they address, so none of the eleven is real. `Array.opIndexPtr` genuinely returns
  `buffer + index`, a view of the payload; what is missing is that loading a pointer VALUE
  through that address ends the borrow, the same rule `indexEscapeInfo` and the member-access
  path already apply through `isDirectBorrowCarrier`.
- Next: instrument `expressionEscapeInfoAt` on the `clipper.swg` reproducer to find which node
  keeps `viaOwnedPayload` alive across the load — reading the paths did not settle it, since both
  the `IndexExpr` element rule and the deref shape look like they should already detach.
- Complete when: `pixel` builds with a written `#[Inline]` honored across files, the `safety` and
  `sanity` suites still reject every case they reject today, and a test covers both directions:
  a pointer stored in a container survives the container's reallocation, and a pointer INTO the
  container does not.
- Related: the inline half is done - `simd/backlog-sweep`, "Honor a written '#[Inline]' across
  files".
