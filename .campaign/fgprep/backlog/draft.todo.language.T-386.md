# Draft — append to backlog/todo.language.md (end of file, after T-012)

Re-verify the identifier before filing: T-386 assumes the counter still reads
`Next identifier: T-386` in backlog/README.md; advance it to T-387 in the same commit.

---

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
  migration time), `dref me += ...` in operator bodies, guarded element access spelled
  `.buffer![0]`, and the `opIndexPtr` place-context rules (member access, address-of,
  assignment target, nested index) that pick the pointer path without a visible mark.
- Candidate directions, none decided: a postfix lvalue-deref (Zig's `v.*`, Pascal's `v^`) so a
  dereference composes left-to-right with member and index access instead of prefixing the
  whole expression; treating a pointer binding as an assignment target directly (auto-deref on
  the left of `=`, the road C++ references and D's `ref` took — the one to weigh most
  carefully, since an invisible deref is how a second indirection type grows back); a dedicated
  loop-binding spelling that writes through without `dref`. An explicit by-value parameter
  spelling for a callee that wants a scratch copy belongs to the same review (struct parameters
  now pass by value with a const-address ABI, so the callee still cannot mutate its copy).
- The decision to make: which of these, if any, earns its place, judged against the inventory
  above; a rejected direction is recorded here with its reason so the question does not reopen
  itemless. Whatever is accepted must keep the invariant the campaign paid for: one indirection
  type, visible at the type level.
