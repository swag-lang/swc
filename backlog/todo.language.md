# Language Roadmap

This file is the roadmap for the Swag language and its syntax, measured against what it competes
with: Rust, Go, Zig, Swift, D, and the self-hosted tier of Jai and Odin. The compiler that
implements it is [todo.compiler.md](todo.compiler.md).

Open compiler defects and language-rule inconsistencies with evidence — the folded `typeinfo ==`
that disagrees with the runtime comparison, nullability that does not survive indirection,
a `#run` write that never reaches the emitted binary — are in
[findings.compiler.md](findings.compiler.md) and are not repeated here. Language rules that behave
exactly as specified and surprise anyway — a positional pattern that ignores the field names it
spells, a grouped default that reaches every name in the group, a `#scope` that swallows `break` —
are in [findings.language.md](findings.language.md). This file holds design questions that are open
by choice rather than by accident.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

---

## Data modeling and exhaustive control flow

### T-009 — Enum switches are silently non-exhaustive

- A `switch` over a three-value enum that handles two of them compiles with no error, no warning,
  and no `default`; the third value simply falls through to nothing. Exhaustiveness exists but is
  opt-in through `switch #complete`
  ([005_005_switch.swg:178](../bin/reference/modules/language/src/005_005_switch.swg#L178)).
- Every language that made exhaustiveness the default — Rust, Swift, Kotlin, and Zig for tagged
  unions — did so because the failure is invisible at the time it is introduced and shows up when
  a value is *added* to the enum later, in code nobody re-read.
- The decision to make: whether `#complete` should be the default for enum switches, with an
  explicit `else` as the opt-out. That is a breaking change with a mechanical migration, and it
  rides on the warning policy layer that now exists (`#[Swag.Warning]`, `cfg.warnings`,
  `--warn-*`) — without one, the only two answers available are "error" and "silence".

### T-010 — There is no tagged union

- `union` is C-style and untagged: all fields share offset 0 and reading a field that was not the
  one written is legal and meaningless
  ([004_006_union.swg](../bin/reference/modules/language/src/004_006_union.swg)). `any` covers the
  dynamic case. There is nothing in between — no discriminated union, no payload-carrying enum,
  no destructuring in `case`.
- Consequence: a sum type has to be hand-encoded as a tag next to an untagged union, and the
  invariant lives in a comment. `pixel`'s painter command is exactly that — `id: CommandId`
  followed by `using params: union`, documented as "Command-specific payload selected by `id`;
  inactive members must not be read"
  ([painter.swg:147-149](../bin/std/modules/pixel/src/painter/painter.swg#L147-L149)). Nothing
  checks that sentence. Rust, Swift, Zig and modern C# all consider the checked version table
  stakes; it is arguably the single largest expressiveness gap in the language.
- It interacts with T-009 (a tagged union is where exhaustive matching earns its keep) and with
  the error-handling design already shipped (`fail`/`try`/`catch`), which chose a different axis
  and should not be re-litigated by the same feature.

## Generic contracts and execution semantics

### T-011 — The generic instantiation chain omits the call site

- The diagnostic is already better than most: it reports the error inside the generic *and*
  attaches a note naming the specialization (`while checking generic function 'doubleIt' with
  T = Point`). What it does not do is name the call site that caused the instantiation — the one
  line the user has to change. Adding that frame to the instantiation chain is a small, immediate
  win.
- Related: T-121

### T-121 — Generic constraints cannot name a required interface

`where` is a compile-time boolean over generic parameters
([009_003_where_constraints.swg](../bin/reference/modules/language/src/009_003_where_constraints.swg)).
There is no declaration-site way to state that `T` must provide a member or satisfy a named
contract, so a missing operation fails only inside an instantiation. Decide named contracts versus
predicates after T-011 makes the current model's diagnostics complete.

- Related: T-011

### T-012 — The concurrency model is undecided

- The library omissions are split into T-036 (tasks), T-160 (channels), T-161 (condition
  variables), and T-162 (asynchronous I/O). This entry owns only the language-level concurrency
  decision that must precede those API choices.
- Go answered with goroutines and channels, Rust with `async` and a futures machinery that reaches
  into the type system, .NET with `Task`. Each answer changed the language, not just the library.
- The forcing function is already scheduled: [T-027](todo.core.md#t-027--no-blocking-tcp-sockets) puts
  non-blocking sockets on the path, and deciding this *under* that pressure is how languages end up
  with two concurrency models. Decide it early and deliberately, and record the decision here.

## Pointer-model ergonomics

### T-386 — The pointer-only world shipped without sugar, and the friction is uninventoried

- The noref campaign removed reference types entirely: the one indirection is the non-null
  pointer `*T`, a struct element binds as `const *T` under `for v` and `*T` under `for &v`,
  a scalar write through a binding spells `dref v = x`, and `me` is a non-null pointer. The
  migration was deliberately sugar-free so the bare model could be judged on real code before
  any spelling is added — proposals were explicitly deferred to after the functional
  migration, and this entry owns them.
- The inventory comes from the migration diff, not from invented examples: the `for &v` bodies
  across `bin/` whose scalar writes became `dref v = x` or `dref v *= k` (~168 sites at
  migration time), `dref me += ...` in operator bodies, guarded element access, and the
  `opIndexPtr` place-context rules (member access, address-of, assignment target, nested index)
  that pick the pointer path without a visible mark.
- Decided and shipped: the postfix lvalue-deref, spelled `expr[]` (empty brackets open the
  pointed storage as a read/write place, composing left-to-right with member and index
  access), together with `expr[as T]` which opens the same place reinterpreted as a `T`.
  `dref` remains the prefix spelling of the same operation.
- Candidate directions still undecided: treating a pointer binding as an assignment target
  directly (auto-deref on the left of `=`, the road C++ references and D's `ref` took — the
  one to weigh most carefully, since an invisible deref is how a second indirection type
  grows back); a dedicated loop-binding spelling that writes through without a deref mark.
  A parameter mode that gives the callee a mutable scratch copy belongs to the same review
  (struct parameters use a const-address ABI, so the callee cannot mutate the value it
  receives).
- The decision to make: which of these, if any, earns its place, judged against the inventory
  above; a rejected direction is recorded here with its reason so the question does not reopen
  itemless. Whatever is accepted must keep the invariant the campaign paid for: one indirection
  type, visible at the type level.
