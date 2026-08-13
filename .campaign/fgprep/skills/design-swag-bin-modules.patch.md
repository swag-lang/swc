# noref stage F — skill patch: design-swag-bin-modules (slice B)

File: `.agents/skills/design-swag-bin-modules/SKILL.md` (branch `noref`).
Prepared read-only on 2026-08-13. NOTES says "design-swag-bin-modules si mention" — the audit
found NO passage that names the reference type, so no replacement is REQUIRED. One RECOMMENDED
edit adds the operation-family axis the campaign introduced across `bin/std` collections.

## Audit result — no required edit

Grep of the whole skill for reference-as-a-type language: the only hits are borrow vocabulary
that survives the campaign unchanged —

- line 91: "owned and borrowed inputs or results;" — still correct (borrows are pointers now).
- lines 123-125: "Return borrowed slices, strings, and pointers only when their lifetime has an
  obvious owner. ..." — already stated in pointer terms.
- line 119: "null pointers as applicable" — still correct.

No `&T`, no "reference" type concept, no ref-returning-accessor guidance anywhere in the file.

## Edit — RECOMMENDED (section "Design complete operation families", line 90)

The pointer world gave every element-owning container a pointer-returning place counterpart
(`opIndexPtr` beside `opIndex`, `frontPtr`/`backPtr`/`peekPtr` beside `front`/`back`/`peek`
across array, staticarray, deque, orderedmap, orderedset, priorityqueue). That is now a real
axis of the operation matrix this section tells reviewers to walk, and it is invisible in the
current text.

Old:

```markdown
- mutable and read-only access;
```

New:

```markdown
- mutable and read-only access, including pointer-returning place counterparts when a
  container exposes element storage (`opIndexPtr` beside `opIndex`, in const and mutable
  forms; `frontPtr`/`backPtr`/`peekPtr` beside `front`/`back`/`peek`);
```

## Deliberately not drafted

- No change to "Make contracts hard to misuse": its borrow bullets already speak in pointers
  and owners, and adding pointer-specific mechanics there would duplicate
  `write-idiomatic-swag-code` (which owns the caller-side idioms; see the companion patch).
