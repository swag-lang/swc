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
- Evidence: `pixel/src/poly/clipper.swg` stops compiling. `getLastOutPt` and `addOutPt` read
  `.polyOuts[i]` out of an `Array'#null *OutRec`, dereference the pointer they find there, and
  return an `OutPt` node that `Memory.new` allocated. The analysis records that return as a view
  of `me.polyOuts`, so a later `.addOutPt` or `.intersectEdges` that grows the array reports
  eleven `sanity_err_borrow_invalidated`. Growing an array of pointers moves the pointers, never
  the nodes they address, so none of the eleven is real.
- Already ruled out: the `IndexExpr` route is NOT the lever. Forcing `indexReadsElementByValue`
  to answer true - on the resolved node and on the written one - leaves all eleven in place, so
  the borrow reaches the return without passing the index at all. The summary trace says
  `addReturnBorrowOrigins` receives `viaOwnedPayload=1 payloadField=polyOuts` with the source node
  being the MEMBER ACCESS `.polyOuts`, which is where `ownedPayloadStorageRootAt` sets the flag.
  What is missing is the step that clears it when a pointer VALUE is loaded through that view.
- Next: trace `expressionEscapeInfoAt` over `let outRec = nnOutRec(.polyOuts[i])` and find which
  node carries `viaOwnedPayload` past the load - the argument path of the call is the first
  suspect, since the index rule provably never runs.
- Complete when: `pixel` builds with a written `#[Inline]` honored across files, `bin/unittests/
  sanity` still rejects everything it rejects today, and `borrow_invalidation.swg` keeps both
  directions green.
- Related: the guard on a written `#[Inline]` is restored until this is settled - see
  `simd/backlog-sweep`, "Restore the cross-file inline guard until the borrow analysis is right".
