# Deleting 004_008_references.swg — renumbering and cross-references

Delete: `bin/reference/modules/language/src/004_008_references.swg`.
Nothing in it survives verbatim: the transparent-alias model is gone; the two ideas worth
keeping (element addresses from containers, struct arguments pass with no copy) are absorbed
into the 004_007 draft ("Element Addresses from Containers", "Pointers to Nullable Slots")
and the 006_001 hunk ("Structs as Function Arguments").

## Renumbering

`004_009_any.swg` is the only later file in the 004_ series. Two options:

1. RECOMMENDED: rename `004_009_any.swg` -> `004_008_any.swg` to keep the series
   contiguous (every series in the module is currently gap-free). In-repo, nothing
   references the `004_009` stem except the generated `web/language.html`.
2. Keep the gap: the `.Examples` generator orders files lexically, so a hole is
   harmless; generated anchors for the any chapter then stay stable across the
   already-published site.

Whichever is chosen, no other file in the series moves.

## Cross-references found (whole-repo grep for `004_008`, `004_009`, `references.swg`)

- `web/language.html` — GENERATED file (TOC entries and `_004_008_references_swg*`
  anchors, plus the search index strings). Do not hand-edit; regenerate the site at
  stage G (`tools/web`). Note the transient "user-mapped section" lock when running it.
- `backlog/findings.language.md:422` — finding **F-062** ("Struct parameters are always
  const references, and there is no by-value form") cites
  `004_008_references.swg#L105-L121` and `006_001_declaration.swg#L166-L171` as evidence.
  The link goes stale on deletion, and the campaign itself changes the recorded fact
  (struct parameters are now by-value with a const-address ABI). Update the finding per
  backlog conventions: repoint evidence to the rewritten 006_001 section and record the
  noref campaign as the resolution.
- `.campaign/NOTES.md` — campaign bookkeeping; no action.
- No reference chapter links to another chapter by number, and no toc/index source file
  exists inside `bin/reference` (the TOC lives only in the generated web page), so no
  in-module re-linking is needed.
