# noref stage F — VSCode extension patch (slice A)

Repository: `c:/Perso/swag-lang/swc-noref` (branch `noref`). Prepared read-only on 2026-08-13.
Governing skill: `.agents/skills/reflect-swag-syntax-changes/SKILL.md`.

## Audit scope

Every artifact of the extension was inspected:
`vscode/syntaxes/swag.tmLanguage.json`, `vscode/language-configuration.json`,
`vscode/themes/swag-dark.json`, `vscode/package.json`, `vscode/package-lock.json`,
`vscode/extension.js`, `vscode/src/providers.js`, `vscode/README.md`, `vscode/CHANGELOG.md`
(stub, only "## 0.0.1"), `vscode/.vscodeignore`, `vscode/.vscode/launch.json`,
`vscode/images/syntax.png` (viewed — the screenshot contains no reference-type syntax),
`vscode/images/swag_icon.png`. There are no snippets and no hover/completion data files.

## Finding 1 — `&T` removal requires NO grammar edit (verified)

The grammar has no type-context rule of any kind and no rule that highlights `&` as a
reference-type former. The only occurrence of `&` in `swag.tmLanguage.json` is the generic
operator class (line 527):

```json
"operator-character": {
  "patterns": [
    {
      "name": "keyword.operator",
      "match": "[\\/=\\-+!*%<>&|^~.`'!:]"
    }
  ]
}
```

This rule MUST stay unchanged: `&` survives the campaign as the address-of operator
(`let renderer: IRenderer = &cpu`, `sort(&items[i])`, `=> &.find(key).value`) and as
bitwise-and.

Do NOT add an "invalid `&` in type position" rule. The grammar is line-regex based with no
notion of type context; any such pattern would false-positive on address-of and bitwise-and.
The new parser diagnostic ("references were removed; use a pointer '*T'", stage A of NOTES) is
the authority.

Other lists checked and confirmed campaign-clean:

- `keywords` (line 119) already contains `dref`, which the pointer world promotes:
  `"match": "\\b(using|with|cast|dref|retval|try|catch|expect|fail|discard)\\b"` — no change.
- `compiler-modifiers` (line 260) contains `move`, `relocate`, `fwd`, which MUST remain
  (`#move`/`#fwd`/`#relocate` and the internal MoveReference are kept per "Décisions
  arrêtées"): `"match": "\\#(prom|wrap|nodrop|move|relocate|fwd|bit|unconst|null|complete|fail|nofail|raw)\\b"`
  — no change.
- No `ref`, `moveref`, or reference-related spelling exists anywhere else in the grammar.

## Finding 2 — REQUIRED edit: add `opIndexPtr` to the `op` rule

The pointer world replaces ref-returning `opIndex` with `opIndexPtr` pairs
(`mtd opIndexPtr(index: u64)->*T` / `mtd const opIndexPtr(index: u64)->const *T`; 10
declarations already live in `bin/std` — array, staticarray, orderedmap, orderedset, ...).
The grammar's `op` rule (line 308) does not list it, and the `op-invalid` rule (line 316)
scopes any unlisted `op[A-Z]\w*` as `invalid` — so today every `opIndexPtr` declaration and
call renders as an error in the editor.

File: `vscode/syntaxes/swag.tmLanguage.json`, repository `op` (single `match` line).

Old fragment (exact, line 308):

```json
          "match": "\\b(opSlice|opBinary|opBinaryRight|opUnary|opAssign|opIndexAssign|opIndexSet|opCast|opCount|opData|opVisit|opInit|opReloc|opEquals|opCompare|opPostCopy|opPostMove|opDrop|opCount|opSet|opSetLiteral|opIndex|opIndexAssign)\\b"
```

New fragment (adds `opIndexPtr` after `opIndex`; the trailing `\\b` keeps alternation order
safe either way):

```json
          "match": "\\b(opSlice|opBinary|opBinaryRight|opUnary|opAssign|opIndexAssign|opIndexSet|opCast|opCount|opData|opVisit|opInit|opReloc|opEquals|opCompare|opPostCopy|opPostMove|opDrop|opCount|opSet|opSetLiteral|opIndex|opIndexPtr|opIndexAssign)\\b"
```

Pre-existing, unrelated: `opCount` and `opIndexAssign` each appear twice in this alternation.
Harmless duplicates; leave them unless a broader cleanup is wanted (do not bundle it into the
campaign diff without asking).

## Finding 3 — REQUIRED follow-up: version bump + package + install

The grammar changes, so per skill section 3 the extension must be rebuilt and installed or
highlighting stays stale.

File: `vscode/package.json`.

Old fragment (line 5):

```json
  "version": "0.0.149",
```

New fragment:

```json
  "version": "0.0.150",
```

Then, from `vscode/` (apply-time commands, for the applying agent — the build slot is not
needed, but coordinate with the agent working in the repo before touching files):

```bash
vsce package --allow-missing-repository --no-dependencies
code --install-extension swag-0.0.150.vsix --force
```

Confirm the install line reports success.

## Artifacts required by reflect-swag-syntax-changes — full checklist

Section 1 of the skill (language reference, `bin/reference/modules/language/src/`) — owned by
the stage-F DOC slice per NOTES ("F. Doc + VSCode + skills"); listed here for completeness
with the verified grammar-agreement facts:

1. `004_008_references.swg` — DELETE; absorb the useful remainder into `004_007_pointers.swg`
   (opIndexPtr, indexing through `*T`). (Doc slice.)
2. `004_007_pointers.swg` — rewrite the "reference is transparent" section (lines 158-196).
   (Doc slice.)
3. `005_003_for_elements.swg` — `for &v` now binds the element address (`*T`); `for v` on
   structs binds `const *T`. (Doc slice.)
4. `006_005_operator_overloading.swg` — document `opIndexPtr`. (Doc slice.)
5. `006_008_custom_iteration.swg` — `ptr: bool` opVisit protocol, `cast(*T)` injects.
   (Doc slice.)
6. `006_009_custom_copy_and_move.swg` — `&Vector3` example becomes `*Vector3` + `dref`.
   (Doc slice.)
7. `007_006_ufcs.swg` — pointer receivers. (Doc slice.)
8. `013_004_*` borrowing chapter — remove "reference" from the list of views. (Doc slice.)
9. `002_007_keywords.swg` — VERIFIED: needs no edit for grammar agreement. `&` was never a
   keyword; `dref` is already catalogued (line 37); `#move`/`#fwd` stay. Any prose touch-up is
   doc-slice work.
10. `002_008_sigils.swg` — VERIFIED: contains no `&` and no reference-type entry; no edit.

Section 2 of the skill (the extension) — THIS slice:

11. `vscode/syntaxes/swag.tmLanguage.json` — one required edit (Finding 2). No `&`-type edit
    exists to make (Finding 1).
12. `vscode/language-configuration.json` — VERIFIED no change (comments/brackets only).
13. `vscode/themes/swag-dark.json` — VERIFIED no change (scope-to-color map; no
    reference-specific scope).
14. `vscode/README.md`, `vscode/CHANGELOG.md`, `vscode/extension.js`,
    `vscode/src/providers.js`, `vscode/images/syntax.png` — VERIFIED no change (no
    reference-type mention or depiction; README's "language reference" means the docs).

Section 3 of the skill (rebuild + install) — required because the grammar's name lists
changed (Finding 3).

Done criteria for this slice: grammar lists `opIndexPtr`; `&` stays a plain operator; version
bumped; `.vsix` packaged and installed; the doc-slice items 1-8 land with the stage-F doc
work so the reference and the grammar stay in agreement.
