# Structural compilation savings, 2026-10-20

This prompt-4 session starts at `71f642e258`, on `perf/prompt4-20261020` in an
external worktree. Planned compiler work uses its checkout-local DevMode compiler
and at most six workers. `SWC_BUILD_NUM` remains 1173. No timing, profiler, or
benchmark campaign is run; compilation-time targets remain unverified.

| Retained change | Compiler work removed | Equivalence and storage evidence |
| --- | --- | --- |
| Initialize conservative CFG reachability with its final value | Zeroing every instruction byte immediately before filling the same bytes with ones | The existing conservative predicate selects the initial byte. Supported graphs retain their zero initialization and traversal; missing roots retain their later all-ones fallback. The DevMode function shrinks from 1,197 to 1,151 code bytes with the same 112-byte stack reservation. |

Validation uses fresh machine-load admission before each command. C++ tests use
isolated temporary/cache roots. The default C++ suite omits filesystem tests
requiring `--dev-full`.

The first retained batch builds successfully and passes all 1,486 C++ tests,
including a new reachability regression covering multiple/duplicate roots,
detached instructions, absent roots, unresolved jumps and address-taken labels.
The discarded index-list trial also passed seven focused native tests; those
results are not a validation claim for a retained index-list change.

Rejected trials:

- Returning a separately constructed all-ones reachability vector duplicated
  generated construction code and grew the frame. The retained version constructs
  one vector with the predicate-selected initial byte.
- Borrowing index-list AST chunks removed their temporary reference vector and
  reduced the frame, but grew the generated caller body. Both the initial form and
  a form sharing initial header decoding were discarded. The original index-list
  implementation is restored.
