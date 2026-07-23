---
name: write-swag-compiler-messages
description: Write, review, and refactor English text emitted by the Swag compiler in its precise, calm voice. Use for diagnostic catalogs, errors, warnings, notes, help, source spans, generic or overload reports, macro/mixin/#ast/generated-code reports, command-line help, configuration descriptions, progress output, runtime safety reports, crash text, developer validation output, and tests that protect user-facing wording.
---

# Write Swag Compiler Messages

Make every message concise on the surface and exact underneath. Swag is direct without sounding cold, clever without jokes, and helpful without lecturing.

## Establish The Local Contract

1. Read and follow [../modify-swag-codebase/SKILL.md](../modify-swag-codebase/SKILL.md).
2. Inventory both catalogs and direct output. Do not assume all user-facing text lives in diagnostic files.
3. Exclude machine protocols, encoded symbol names, source-language keywords, required platform spellings, and unowned third-party text.

Typical surfaces include:

- `src/Support/Report/Msg/*.msg`
- diagnostic builders, assertion reports, and hardware-exception reports
- semantic, generic, overload, code-generation, linker, and JIT paths
- command descriptions, usage, and configuration help
- progress, statistics, dry-run, test, and developer-validation output
- runtime panic, stack trace, safety, and allocator reports

## Preserve The Information Contract

Before rewriting, identify and preserve:

- every dynamic placeholder and its meaning
- the actor and the contract that does not hold
- the operation that stops
- actual and required values, types, counts, ranges, or candidates
- constraints, defaults, exclusions, side effects, and platform limits
- source and generated-source provenance
- every actionable recovery path
- diagnostic identifiers, severities, and significant variant ordering

Add a new diagnostic or test case only when a distinct contract or materially different source presentation needs representation.

## Use The Swag Voice

- Name the actor and broken contract: `array access provides 3 indices, but the array needs 2`.
- Prefer exact verbs such as `needs`, `does not accept`, `does not fit`, `cannot resolve`, `stops here`, and `originates here`.
- Avoid blanket labels such as `invalid`, `unexpected`, `failed`, `failure`, `wrong`, `must`, `mismatch`, `type mismatch`, or `not viable` when the actual disagreement is known.
- Never joke, apologize, blame the programmer, use contractions, or add conversational filler.
- Keep one idea in the primary message. Move provenance to notes and actionable repair to help.

## Shape The Narrative

Start diagnostic prose with lowercase text unless a source token, placeholder, proper technical name, or acronym leads it. Omit terminal punctuation.

Give each diagnostic level one responsibility:

1. `error` or `warning` states the contract that does not hold.
2. `note` identifies the origin of a requirement, prior decision, conflict, or expansion.
3. `help` gives a concrete action only when one is known.

Embed catalog help exactly as `; [help] <imperative action>`. Do not repeat the primary message in a note or add help that merely restates a language rule.

Start command and configuration descriptions with an action verb, preserve every condition and side effect, and omit terminal punctuation. Use short noun labels and lowercase state values in status tables.

## Handle High-Value Diagnostics

For generics and overloads, expose the decision path instead of dumping candidates:

```text
error: cannot deduce generic parameter 'T': argument 2 has type 'string', but argument 1 previously deduced 's32'
note: candidate 'map(func(T) T, []T)' stops here: parameter 'fn' needs 'func(s32) s32', but argument 2 has type 'func(string) string'
help: make the argument types agree, or specify 'T' explicitly
```

- State what could not be deduced or selected.
- Show the actual and required type at the decisive argument.
- Identify where a prior deduction or constraint originated.
- Summarize each relevant candidate at the first reason it stops.
- Omit irrelevant candidates and repeated facts.

For macros, mixins, `#ast`, and generated source:

- Report the generated-code failure first.
- Distinguish generated code from user code.
- Retain the relevant expansion chain, user call site, and root origin.
- Suppress repeated intermediate frames that add no new fact.
- Expose implementation detail only for a genuine compiler invariant failure.

For internal compiler failures, name the phase and precise unavailable artifact or broken invariant. Reserve `internal compiler error` for compiler defects.

## Review Source Presentation

Underline the smallest expression or token that proves the primary statement. Do not underline punctuation or an entire declaration when one operand, argument, name, or delimiter is decisive.

Add a secondary span only when it answers a separate question, such as where a type was fixed, a symbol was declared, or generated code originated.

Add cases under `bin/unittests/errors` for meaningful source-diagnostic variants such as end-of-line recovery, alternate syntax contexts, ambiguous spans, generic deduction conflicts, overload stopping points, and generated expansion provenance. Test command-line, linker, backend, runtime, and internal-only diagnostics at their real boundaries.

## Verify The Result

1. Compare old and new messages for identifiers, severities, placeholders, constraints, values, side effects, provenance, and recovery paths.
2. Exercise representative diagnostics and inspect labels, ordering, underlines, notes, help, wrapping, and generated-source frames.
3. Inspect affected command and configuration help directly.
4. Complete the validation required by `modify-swag-codebase`.
5. Report any intentional information-contract change explicitly.

Do not finish while a user-facing surface remains unreviewed or a required validation is red.

## Review Checklist

- Can an experienced programmer understand the broken contract from the first line?
- Are both sides of every disagreement visible?
- Does each note add provenance or a distinct fact?
- Is every help line executable advice?
- Are spans minimal and sufficient?
- Can any clause be removed without losing information?
- Did every placeholder, constraint, and recovery path survive the edit?
