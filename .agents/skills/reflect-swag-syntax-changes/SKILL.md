---
name: reflect-swag-syntax-changes
description: Keep the Swag language reference and the VSCode extension in sync whenever the language's SURFACE SYNTAX changes. Use whenever a keyword, modifier, operator, intrinsic, token spelling, or literal form is added, removed, or renamed in the compiler (typically an edit to src/Compiler/Lexer/Tokens.Def.inc or the parser). A syntax change is not finished until the documentation and the editor grammar match it.
---

# Reflect Swag Syntax Changes

A change to what the language accepts is only half-done in the compiler. The reference
documentation and the VSCode extension are part of the language's surface and must move
with it, or users read wrong docs and see wrong highlighting.

Trigger this whenever you add, remove, or rename any of: a keyword, a `#` modifier, an
`@` intrinsic, an operator, a token spelling, or a literal form. Editing
`src/Compiler/Lexer/Tokens.Def.inc` is the strongest signal.

## 1. Update The Language Reference

The reference lives in `bin/reference/modules/language/src/` and is COMPILED AND TESTED
(each `#test` block runs). So documentation drift is a test failure waiting to happen.

- Update the prose AND the runnable examples for the changed construct in the relevant
  chapter (e.g. error handling in `013_001_*`, operators in `003_006_*`, defer in
  `011_002_*`).
- Update the keyword / modifier / intrinsic catalog in `002_007_keywords.swg` when a
  spelling appears or disappears.
- Add or adjust a `#test` that exercises the new form so the doc proves itself.
- Follow [../write-swag-compiler-messages/SKILL.md](../write-swag-compiler-messages/SKILL.md)
  for any prose, and [../modify-swag-codebase/SKILL.md](../modify-swag-codebase/SKILL.md)
  plus [../validate-swag-changes/SKILL.md](../validate-swag-changes/SKILL.md) for validation
  (`swc tools/reference.swgs dm test` must stay green).

## 2. Update The VSCode Extension

The grammar lives in `vscode/syntaxes/swag.tmLanguage.json`.

- Keyword changes: edit the error-handling / control keyword match lists.
- `#` modifier changes: edit the `compiler-modifiers` match.
- Keep the reference keyword catalog (`002_007_keywords.swg`) and the grammar in agreement.

## 3. Rebuild And Install The Extension (only when keywords/modifiers change)

When a keyword or modifier is added or removed (not for a pure behavior change), a new
extension build must be produced and installed, or highlighting stays stale:

```bash
cd vscode
# bump "version" in package.json (e.g. 0.0.136 -> 0.0.137)
vsce package --allow-missing-repository --no-dependencies
code --install-extension swag-<new-version>.vsix --force
```

`vsce` and the `code` CLI are expected on the machine. Confirm the install line reports
success.

## Finish Cleanly

A syntax change is done only when: the compiler accepts the new form, `reference.swgs dm test`
is green with updated docs, the grammar matches, and (for keyword/modifier changes) the
bumped extension is packaged and installed. Report which of these you completed.
