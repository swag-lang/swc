# noref stage F — skill patch: write-idiomatic-swag-code (slice B)

File: `.agents/skills/write-idiomatic-swag-code/SKILL.md` (branch `noref`).
Prepared read-only on 2026-08-13. Two REQUIRED replacements (the first is the passage NOTES
names explicitly) plus one RECOMMENDED addition codifying the pointer-world idioms this skill
will be asked about constantly after the campaign. All spellings verified against migrated
`bin/std` sources (`*T`, `#null *T`, `dref`, `opIndexPtr`, `frontPtr`/`backPtr`/`peekPtr`) and
the reference-doc vocabulary ("single-value pointers", "block" pointers, `004_007_pointers.swg`).

## Edit 1 — REQUIRED (section "Make Ownership Scope-Bound", lines 145-146)

Old:

```markdown
- Never retain a borrow beyond its owner. Prefer references for non-null borrowed values, nullable
  pointers only for real absence, and slices instead of pointer/count pairs outside native code.
```

New:

```markdown
- Never retain a borrow beyond its owner. Prefer non-null pointers (`*T`) for borrowed values,
  nullable pointers (`#null *T`) only for real absence, and slices instead of pointer/count pairs
  outside native code.
```

## Edit 2 — REQUIRED (section "Keep APIs Hard to Misuse", lines 211-212)

Old:

```markdown
- Prefer values and references at the product layer; isolate raw handles and pointer-heavy shapes
  in native bindings.
```

New:

```markdown
- Prefer values, slices, and single-value pointers (`*T`) at the product layer; isolate raw
  handles and block-pointer (`[*] T`) shapes in native bindings.
```

## Edit 3 — RECOMMENDED addition: a "Borrow Through Pointers" section

Insert as a new `##` section immediately after the "Make Ownership Scope-Bound" section (that
is, after the "### Choose `defer` by what the cleanup is for" subsection and before
"## Use `with` for Construction, Not for Shorthand"). It records the idioms the campaign
established; without it the skill is silent on the only indirection the language now has.

```markdown
## Borrow Through Pointers

`*T` is the only borrowed indirection: it is non-null, member access and method calls read
through it directly, and only a whole-value write needs `dref`.

- Iterate elements as pointers. Over struct elements, `for v in items` binds `const *T` — never
  a copy — and `for &v in items` binds `*T`. Access members and call methods through the binding
  directly; write a scalar element with `dref v = value`.
- Pass structs by value. The ABI hands the callee a const address, so a by-value struct
  parameter costs no copy. Take `*T` only when the callee mutates the caller's value, and write
  the whole pointee with `dref`.
- `me` is a non-null pointer to the receiver. Pass `me` itself where a `*T` is expected; `&me`
  is the address of the receiver slot, never the object.
- Index places directly: `items[i].field = x` and `&items[i]` route through the container's
  `opIndexPtr`. Reach for `frontPtr`/`backPtr`/`peekPtr` when a borrowed element must outlive
  the expression, and the value forms (`front`, `back`, `peek`) otherwise.
```

## Verified non-changes in this skill

- Line 120 `let renderer: IRenderer = &cpu` and lines 125-128 ("Pass the address of the
  concrete instance...", "the required `&`", "borrowed pointer") stay: `&` address-of and
  pointer-borrow vocabulary survive the campaign unchanged.
- No other passage in the skill names references as a Swag type concept (checked: "reference"
  appears nowhere else; no `&T`, `const&`, or `for &` code sample exists in the file).
