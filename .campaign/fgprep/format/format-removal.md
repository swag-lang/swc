# Stage F prep — formatter + parser surfaces of the `&T` reference type

Slice deliverable for the noref campaign (repo `c:/Perso/swag-lang/swc-noref`, branch `noref`).
Scope: every compiler-adjacent place that still formats, parses, or names the reference TYPE
syntax `&T`. `#move`/`#fwd` (`MoveRefType` / internal `MoveReference`) are KEPT everywhere.

> **DO NOT APPLY YET.** Every hunk below is a C++ change to the compiler front end. It requires
> the full C++ validation ladder (DevMode build, `swc tools/tests.swgs dm`, `dm --all-cfg`,
> Release build, `swc tools/tests.swgs`) plus a compiler version bump, and another agent
> currently holds the build/test slot. Apply only when the slot is free, per the agent-to-agent
> serialization rules in `.agents/skills/modify-swag-codebase/SKILL.md`.

---

## 1. Verdict on `src/Format`: nothing to remove

The formatter has **zero reference-type-specific code**. Verified read-only across all 27 files
of `src/Format` (greps for `ReferenceType`, `MoveRefType`, `ValuePointerType`, `Ampersand`,
`reference`):

- The formatter is a token-stream rewriter (`AstSourceWriter` re-emits the lexed pieces;
  `FormatModel` is built from tokens). It never renders a type from the AST, so it never spells
  `&T` itself.
- `FormatClassifier.cpp` classifies no type-syntax node at all — there is no case for
  `ReferenceType`, `MoveRefType`, `ValuePointerType`, or `BlockPointerType` anywhere in its
  `classifyNode` switch. Type tokens ride through unclassified and keep their user spacing.
- The only `&` the formatter knows is the **expression-level unary operator**
  (`src/Format/Pass.Spacing.cpp:29`, `isUnarySymbol` → `FormatRoleE::UnaryOp`, assigned only to
  `AstNodeId::UnaryExpr` at `src/Format/FormatClassifier.cpp:1175-1177`). Address-of `&x`
  survives in the pointer world — **keep this code unchanged**.
- Option descriptions (`FormatOptionsLoader.cpp`) and the canonical style (`FormatStyle.cpp`)
  never mention references.
- Formatter C++ tests (`src/Unittest/Format/*`) contain `&` only as closure captures /
  address-of (`Test.Format.Wrap.cpp:732,744`) — untouched by the removal.

Why the formatter still needs no guard: `swc format` parses each file with the real compiler
parser and **skips any file whose parse reports an error** (`src/Format/FormatJob.cpp:36-43`,
`skippedInvalid_`, counted in `numFormatSkippedInvalidFiles`; parse diagnostics are muted at
`FormatJob.cpp:26`). Once the parser rejects `&T` (section 2), the formatter automatically
refuses to rewrite old-world files, exactly like any other syntax error today. The recovery node
the parser synthesizes (section 2) is irrelevant to formatting: the formatter re-emits tokens,
not AST, and never reaches a file that has errors.

**Conclusion: the "remove `&` type support from swc format" item of NOTES stage F is satisfied
by the parser change alone. No `src/Format` hunk exists.**

## 2. Parser: the single `&T` production and its rejection

### 2.1 Inventory — sites that understand `&` as TYPE syntax

| File | Lines | What | Action |
| --- | --- | --- | --- |
| `src/Compiler/Parser/Parser/Parser.Type.cpp` | 184-194 | `parseSubTypeNoQualifiers`: `&` → `AstNodeId::ReferenceType` (only creation site in the repo) | Replace with dedicated error + pointer recovery (hunk A) |
| `src/Compiler/Parser/Parser/Parser.Expression.cpp` | 54-55 | `canStartSubType`: `SymAmpersand` and `SymAmpersandAmpersand` listed as type starters (used only by `looksLikeArrayTypeExpression` to prefer type parsing after `[...]` in expression position) | Remove both cases (hunk B) |
| `src/Compiler/Parser/Parser/Parser.Expression.cpp` | 965 | `parsePrimaryExpression`: `case SymAmpersand: return parseType()` (type-value expression starter; in practice near-unreachable because `parsePrefixExpr` at line 1071 consumes a leading `&` as address-of first) | Remove the case (hunk C) |
| `src/Support/Report/Msg/Errors.Parser.msg` | 9 | `parser_err_invalid_type` help still names "pointer/reference" as a type starter | Reword (hunk E) |

### 2.2 Inventory — `&` sites that MUST STAY (not type syntax)

- `Parser.Type.cpp:196-230` — `#move` / `#fwd` → `AstNodeId::MoveRefType`. KEEP (campaign decision).
- `Parser.Stmt.cpp:355-362` — `for &v` element binding (`AstForeachStmtFlagsE::ByAddress`). KEEP.
- `Parser.Func.cpp:65-66` — closure capture `|&x|` (`AstClosureArgumentFlagsE::Address`). KEEP.
- `Parser.Expression.cpp:1071-1076` — unary address-of `&expr` in `parsePrefixExpr`. KEEP.
- Lexer `SymAmpersand` / `SymAmpersandAmpersand` tokens (`Tokens.Def.inc:70-72`). KEEP (bitwise
  and, address-of, capture, `for &v`; `&&` is already rejected in favor of `and`).

### 2.3 Recovery choice

Follows the two in-repo precedents for removed syntax:

- `foreach` (`Parser.Stmt.cpp:1007-1014`): report the dedicated diagnostic, then parse as the
  replacement construct.
- `#"..."#` raw strings (`Parser.Literal.cpp:64-68`): keep consuming the old spelling so the rest
  of the statement parses normally; only the spelling is rejected.

So hunk A reports `parser_err_reference_type_removed` at the `&` token, then parses the pointee
and **recovers as if the user had written `*T`** (synthesizes `AstNodeId::ValuePointerType` on
the `&` token). Downstream sema then sees the type the help line tells the user to write, which
minimizes cascade errors. `raiseError`'s `lastErrorToken_` dedup and the `fwdReparseDepth_`
silencing (`Parser.cpp:287-288`) apply as for every other parser diagnostic, so `#fwd` double
parses do not double-report. `& & T` reports once per `&` (different tokens), which is fine.

Note on hunk B: removing `&` from `canStartSubType` means an expression-position
`[3] &A` no longer routes into type parsing (it becomes array-literal `[3]` `&` `A`, a binary
and that sema rejects). The type-position path — the only one real code used — still gets the
dedicated error via hunk A. If the main agent prefers maximum migration friendliness, keeping
`SymAmpersand` there (commented as recovery routing) is also defensible; the draft removes it
because stage F's goal is that the grammar no longer knows `&` as a type.

## 3. New diagnostic

Catalog format (verified): an id line in `src/Support/Report/Msg/Errors.Parser.inc`
(`SWC_DIAG_DEF(name)`) plus one message line per variant in
`src/Support/Report/Msg/Errors.Parser.msg` (`SWC_DIAG_DEF(name, Severity, "text")`).
Both files end with `parser_err_for_selector_removed`; append after it in both to keep the two
files symmetric.

Wording follows `write-swag-compiler-messages`: removal precedent shape "X has been replaced by
Y" (`parser_err_foreach_removed`, `parser_err_raw_string_delimiter`), lowercase start, no
terminal punctuation, `; [help]` with one executable action, no banned verbs.

### Hunk D1 — `src/Support/Report/Msg/Errors.Parser.inc` (append after line 50)

```text
 SWC_DIAG_DEF(parser_err_for_selector_removed)
+SWC_DIAG_DEF(parser_err_reference_type_removed)
```

### Hunk D2 — `src/Support/Report/Msg/Errors.Parser.msg` (append after line 59)

```text
 SWC_DIAG_DEF(parser_err_for_selector_removed, Error, "loop selector '{tok}' is no longer supported; [help] iterate an ordinary view, such as 'value.pairs()' or 'value.reversed()'")
+SWC_DIAG_DEF(parser_err_reference_type_removed, Error, "the '&T' reference type has been replaced by the pointer type '*T'; [help] replace '&' with '*' in the type")
```

The span (added by `raiseError` → `reportError`, `Parser.cpp:276`) underlines exactly the `&`
token — the smallest decisive token, per the skill's span rule.

## 4. Drafted C++ hunks

### Hunk A — `src/Compiler/Parser/Parser/Parser.Type.cpp:182-194`

Old:

```cpp
AstNodeRef Parser::parseSubTypeNoQualifiers()
{
    // Left reference
    const TokenRef tokAmpRef = consumeIf(TokenId::SymAmpersand);
    if (tokAmpRef.isValid())
    {
        const AstNodeRef child = parseSubType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::ReferenceType>(tokAmpRef);
        nodePtr->nodePointeeTypeRef = child;
        return nodeRef;
    }
```

New:

```cpp
AstNodeRef Parser::parseSubTypeNoQualifiers()
{
    // '&T' reference types have been removed from the language; the only indirection is the
    // non-null pointer '*T'. Keep consuming the old spelling for the dedicated diagnostic and
    // recover by parsing the rest as a pointer type.
    const TokenRef tokAmpRef = consumeIf(TokenId::SymAmpersand);
    if (tokAmpRef.isValid())
    {
        raiseError(DiagnosticId::parser_err_reference_type_removed, tokAmpRef);
        const AstNodeRef child = parseSubType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::ValuePointerType>(tokAmpRef);
        nodePtr->nodePointeeTypeRef = child;
        return nodeRef;
    }
```

(The `#move` branch at lines 196-206 and the `#fwd` branch at 208-230 stay byte-identical.)

### Hunk B — `src/Compiler/Parser/Parser/Parser.Expression.cpp:38-62` (`canStartSubType`)

Old (lines 51-56):

```cpp
            case TokenId::KwdConst:
            case TokenId::ModifierNullable:
            case TokenId::SymAsterisk:
            case TokenId::SymAmpersand:
            case TokenId::SymAmpersandAmpersand:
            case TokenId::SymLeftBracket:
```

New:

```cpp
            case TokenId::KwdConst:
            case TokenId::ModifierNullable:
            case TokenId::SymAsterisk:
            case TokenId::SymLeftBracket:
```

### Hunk C — `src/Compiler/Parser/Parser/Parser.Expression.cpp:961-967` (`parsePrimaryExpression`)

Old:

```cpp
        case TokenId::KwdConst:
        case TokenId::KwdStruct:
        case TokenId::KwdUnion:
        case TokenId::SymAsterisk:
        case TokenId::SymAmpersand:
        case TokenId::ModifierNullable:
            return parseType();
```

New:

```cpp
        case TokenId::KwdConst:
        case TokenId::KwdStruct:
        case TokenId::KwdUnion:
        case TokenId::SymAsterisk:
        case TokenId::ModifierNullable:
            return parseType();
```

### Hunk E — `src/Support/Report/Msg/Errors.Parser.msg:9` (`parser_err_invalid_type` help)

Old:

```text
SWC_DIAG_DEF(parser_err_invalid_type, Error, "expected a type here; found {tok-fam} '{tok}'; [help] types can start with a builtin type, identifier or qualified name, pointer/reference, array, 'func', 'mtd', 'struct', or 'union'")
```

New:

```text
SWC_DIAG_DEF(parser_err_invalid_type, Error, "expected a type here; found {tok-fam} '{tok}'; [help] types can start with a builtin type, identifier or qualified name, pointer, array, 'func', 'mtd', 'struct', or 'union'")
```

(NOTES stage D lists this reword; it belongs naturally in the same commit as hunk A.)

## 5. Test corpus impact (must land in the SAME change)

### 5.1 Existing parse-only corpus breaks

`bin/unittests/parser/declarations/type.swg` is the only file under `bin/unittests/parser` and
`bin/unittests/lexer` that uses reference TYPE syntax (full `&` sweep done; the `&point` in
`bin/unittests/parser/flow/with.swg:53` is address-of and stays). Delete these five lines —
their `*` equivalents are already covered by lines 13-14, 30-44, 51-54:

- line 23: `enum A : &A { Z }`
- line 39: `enum A : &*A { Z }`
- line 43: `enum A : [..] &A { Z }`
- line 44: `enum A : [?] &A { Z }`
- line 52: `enum A : & & A { Z }`

Keep lines 24 and 40 (`#move A`, `#move *A` — MoveRefType stays).

### 5.2 New error test (NOTES stage E "erreur `&T` en type (parser)")

New file `bin/unittests/errors/parser/parser_err_reference_type_removed.swg`, following the
convention of `parser_err_foreach_removed.swg` / `parser_err_invalid_type.swg`:

```swag
#global private

// Reference types were removed from the language; '*T' is the only indirection.
func f(x: &s32) {}                  // swc-expected-error {{parser_err_reference_type_removed}}
enum A : &A { Z }                   // swc-expected-error {{parser_err_reference_type_removed}}

#test
{
    var v: [..] &s32                // swc-expected-error {{parser_err_reference_type_removed}}
}
```

(Three distinct source presentations: parameter type, enum underlying type, array/slice element —
matching the skill's guidance on meaningful source-diagnostic variants.)

## 6. Downstream dead code — hand off to stage D, do NOT touch now

Once hunk A lands, `AstNodeId::ReferenceType` is never created, so every consumer below is dead
but still compiles. They reference the `AstReferenceType` struct, so they can only be deleted
together with the node definition; batch them with the `TypeInfoKind::Reference` removal
(NOTES stage D) rather than into the stage F parser commit:

- `src/Compiler/Parser/Ast/AstNodes.Def.inc:35` — `SWC_NODE_DEF(ReferenceType, ...)`
- `src/Compiler/Parser/Ast/AstNodes.Struct.inc:977-984` — `struct AstReferenceType`
- `src/Compiler/Sema/Ast/Sema.Type.cpp:252-259` — `AstReferenceType::semaPostNode`
  (calls `TypeInfo::makeReference`)
- `src/Compiler/Sema/Helpers/SemaClone.cpp:2168-2174` — `AstReferenceType::semaClone`
- `src/Compiler/Sema/Helpers/SemaHelpers.Type.cpp:30` — `isTypeSyntaxNode` case
- `src/Compiler/Sema/Helpers/SemaHelpers.Type.cpp:1156-1160` — `structuralTypeRefFromTypeNode`
  branch (calls `TypeInfo::makeReference`)
- `src/Compiler/Sema/Generic/SemaGeneric.Deduce.cpp:130-131` — pattern peel branch
- `src/Compiler/Sema/Generic/SemaGeneric.Deduce.cpp:1072-1077` — `deduceFromTypePattern` branch
  (guarded by `argType.isReference()`, unreachable once the kind is gone)
- `src/Compiler/Sema/Helpers/SemaSpecOp.Generated.cpp:540-541` — first-param type peel

Stage D caveat to record: removing the `SWC_NODE_DEF` line renumbers every later `AstNodeId`;
verify no serialized artifact (tagbin wire format, `.swagdbg`, cached ASTs) bakes node id values
before renumbering.

Type-name printing of `&T` (user-visible spelling in diagnostics) lives behind
`TypeInfoKind::Reference` in `src/Compiler/Sema/Type/TypeInfo.cpp`, not in the parser or
formatter — stage D removes it with the kind. Sema catalog entries `sema_err_ref_missing_init`,
`sema_err_const_ref_type`, `sema_err_move_arg_param_not_move`, and the `sema_err_assign_to_const`
help ("accept a reference to mutate the caller's value" → pointer wording) are likewise stage D
per NOTES.

## 7. Adjacent surfaces checked and already clean

- `vscode/syntaxes/swag.tmLanguage.json` — `&` appears only inside the generic operator
  character class (line 527); there is no reference-type highlighting. The NOTES stage F
  question "does `&` type highlighting exist?" is answered: no, nothing to change.
- `src/Doc` — code rendering is token-based; no `&T` understanding.
- `src/Unittest` (C++ suites) — no test exercises `&T` parsing or `ReferenceType`.
- Formatter test corpus and options — clean (section 1).

## 8. Validation plan for whoever applies this (when the build slot is free)

The parser sits under every compiled program, so this is a full-ladder C++ change
(`modify-swag-codebase` / "Validate C++ Changes"):

1. Bump the compiler version (one bump per executed binary; stage 2 re-bump already planned).
2. Compile DevMode; run `swc tools/tests.swgs dm`, then `dm --all-cfg`.
3. Compile Release including `swc.exe`; run `swc tools/tests.swgs`.
4. The new error test and the trimmed `type.swg` are covered by the parser/errors suites within
   that run; additionally spot-check the diagnostic rendering (underline on `&`, help line) on a
   probe file.
5. `swc format` behavior on an old-world file needs no dedicated test: it reuses the parser and
   skips files with parse errors (existing contract, `FormatJob.cpp:36-43`).

Integration-gate runs (`--all-cfg`, Release) remain the user's call per project rules; do not
launch them by default.
