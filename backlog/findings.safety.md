# Findings — Safety

The borrow, lifetime, and sanity analyses: what they judge, what they miss, and what they refuse
to judge at all. The language-level decision about which of these checks is part of Swag rather
than tooling is entry 5 of [todo.language.md](todo.language.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-032 — A by-value owning argument carries no borrow, so its payload escapes unjudged

- Area: compiler
- Found while: closing the container-of-views hole F-027 described (now detected: a store into a
  container's `[*] T` payload is summarized, and judged wherever the container outlives what was
  stored into it)
- Observation: `typeCanCarryBorrow` excludes structs with an owning lifecycle, so an argument of
  such a type produces no borrow at a call site. A callee that hands back its parameter's owned
  payload records the return summary correctly, but no call site is ever judged against it.
  Passing the same value by POINTER works, because a pointer is a carrier.
- Evidence: `borrowEscapeHeapParamPayload(box: BorrowEscapeHeapBox)->[*] BorrowEscapeSlot`
  returning `box.slots!` is silent at every call site, while the `*BorrowEscapeHeapBox` spelling
  right next to it errors ([borrow_escape.swg](../bin/unittests/sanity/borrow_escape.swg), section
  "Owned payloads"). The exclusion dates from the field-scan rule: a bitwise walk of an owner's
  fields would confuse ownership with borrowing.
- Next step: the exclusion is about SCANNING an owner's fields, not about the owner being unable
  to lend anything — a by-value owning argument should yield a borrow rooted at that argument
  without the field scan, the way `typeHasBorrowableStorage` already does for owner views. Try it
  behind the usual sweep (build every workspace, zero-hit baseline) and triage: the risk is that
  every owner passed by value starts feeding the stores and frees summaries.

### F-035 — The borrow-invalidation check is built but still fires on nothing

- Area: compiler
- Found while: building the borrow-invalidation check (a view read after the storage it views was
  moved), on branch `worktree-safety-push`
- Observation: the mechanism is complete, the `reallocatesParamsMask` summary crosses module
  boundaries as the fifth `#[Swag.BorrowSummary]` argument, and mapping the body `me` to the
  signature receiver took `core` from 4 functions carrying the bit to 65, `String.reserve` and
  `String.append` among them. The check still reports nothing, and three separate things are in the
  way.
  (1) The request variable an allocator call is handed carries NO borrow when the freed pointer is
  an owned payload: in a self-contained `Owner.grow` doing `req.address = .buffer` then
  `itf.free(&req)`, the seed sees `kind=None`. Ruled out: the nullability narrowing of an enclosing
  `if .buffer` (removing the guard changes nothing).
  (2) The check only considers views whose tracked info `isLocalBorrow()`. A view obtained from a
  method (`tbl.tryFind(...)`, `arr.toSlice()`) is bound as a `DeferredCall`, so the most common way
  to take a view into a container is not a candidate at all.
  (3) A scratch module compiled with `swc test -d <dir>` resolves `swag@std` OUTSIDE the worktree,
  so probes there silently measure the main checkout's standard library. Any probe of a summary
  that crosses a module boundary has to live in `bin/unittests`, or it measures the wrong compiler.
- Evidence: `[seed] reqVar=1 kind=0 owned=0` in a hand-written owner whose `grow` frees its own
  buffer through `IAllocator.free`; the generated `core.swg` carries `BorrowSummary(1, 0, 0, 0, 1)`
  on `String.append` while the importing module reads every mask of that same function as zero,
  which (3) explains.
- Next step: start at (1), since without it the summary is empty whatever else is fixed — trace
  `applyAssignment` for `req.address = .buffer` and find where the owned-payload info is dropped
  between `expressionEscapeInfoWithTarget` and `setProjectionEscapeInfo`. Then (2): bind a view from
  a call as a real borrow of the receiver when the callee's return summary says so, reusing the
  deferred judgement the check already has. Only then does the false-positive cost become
  measurable, and that is the whole point — every workspace is clean today because nothing fires,
  which proves nothing. Two shapes must stay silent when it does: an interface or pointer to the
  value itself (`let r: IRenderer = &cpu; cpu.begin(...)`), and a method that only reads or assigns
  fields (`host.mouseDown` with a view of `host.root`'s metrics).
