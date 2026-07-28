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
- Avoid blanket labels such as `invalid`, `unexpected`, `failed`, `failure`, `wrong`, `must`, `mismatch`, `type mismatch`, or `not viable` when the actual disagreement is known.
- Never joke, apologize, blame the programmer, use contractions, or add conversational filler.
- Keep one idea in the primary message. Move provenance to notes and actionable repair to help.

## Use The Verb Table

Swag says the same thing the same way every time. A reader recognizes a Swag diagnostic by its
verbs alone, so the table below is closed: state a relation with the verb that owns it, and never
with a synonym.

### Requirement — what a site imposes

| Verb | Use it when | Shape |
| --- | --- | --- |
| `needs` | the site requires something it did not get; it may enumerate the alternatives | `'#ast' needs a string, found '{type}'` |
| `accepts` | the message can publish the site's whole domain, as a count or a value set, and the input falls outside it | `'{sym}' accepts {count} arguments, found {value}` |
| `does not accept` | the negative form of `accepts`, when naming the rejected value reads better | `argument '{arg}' does not accept value '{value}'` |
| `can only` | the site itself is restricted to one place or form | `'{tok}' can only be used in the module setup file` |

### Disagreement — what is there against what is required

| Verb | Use it when | Shape |
| --- | --- | --- |
| `has type` … `but` … `needs` | the canonical two-sided sentence; reach for it first | `expression has type '{type}', but this context needs '{requested-type}'` |
| `provides` / `holds` | naming what the source side actually supplies | `source provides {count} fields, destination needs {value}` |
| `does not fit` | the value is well-formed but does not go into the target | `integer compiler tag '{arg}' does not fit type '{type}'` |
| `overflows` / `exceeds` | the value passes a numeric limit; keep `overflows` for types and `exceeds` for sizes and maxima | `literal '{value}' overflows type '{requested-type}'` |
| `found` | the actual token or value at the decisive position | `expected '{expect-tok}' {because}; found {tok-fam} '{tok}'` |

### Absence

| Verb | Use it when | Shape |
| --- | --- | --- |
| `has no` | the container lacks the member | `struct '{requested-type}' has no field '{value}'` |
| `is missing` | the input omitted a required element | `{what} for '{requested-type}' is missing required field '{value}'` |

### Impossibility

| Verb | Use it when | Shape |
| --- | --- | --- |
| `cannot <exact verb>` | the operation cannot happen; the verb names that operation | `cannot cast from '{type}' to '{requested-type}'` |
| `cannot resolve` | a name, overload, or deduction has no answer | `cannot resolve an auto scope in this context` |
| `cannot deduce` | a generic parameter has no consistent binding | `cannot deduce generic parameter '{value}'` |

Never write `cannot be done`, `is not possible`, or `cannot be used` when the real operation has a
name. `cannot be used` is acceptable only where the operation genuinely is "use".

### Property — what does not hold of a well-formed thing

| Verb | Use it when | Shape |
| --- | --- | --- |
| `is not <property>` | the code is valid, but lacks a property the operation depends on | `cannot assign to this expression because it is not assignable` |
| `does not <exact verb>` | the mirror of `cannot`, when the subject is the thing rather than the operation | `cannot cast from '{type}' to interface '{requested-type}', because the struct does not implement it` |

### Capability — what the implementation can handle

| Verb | Use it when | Shape |
| --- | --- | --- |
| `does not support` | the compiler, backend, or target cannot handle the construct at all | `native backend does not support this target OS` |
| `only supports` | the same limit stated positively, when the supported set is short enough to name | `native backend only supports x86_64 targets` |

Keep this family for implementation limits. A rule of the language is not a lack of support: say
what the language does instead.

### Conflict

| Verb | Use it when | Shape |
| --- | --- | --- |
| `already` | the same thing was declared, specified, or initialized before | `modifier '{tok}' is already specified` |
| `conflicts with` | two decisions are individually legal but incompatible | `access modifier '{tok}' conflicts with an earlier one` |

### Provenance — notes only

| Verb | Use it when | Shape |
| --- | --- | --- |
| `is here` | pointing at a previous occurrence of the same kind of thing | `previous definition of '{tok}' is here` |
| `is declared here` | pointing at the declaration that fixed a requirement | `required field '{value}' is declared here` |
| `originates here` | pointing at where a value or constraint came from | `argument outside the accepted domain originates here` |
| `stops here` | the point at which a candidate is eliminated | `candidate '{sym}' stops here: accepts {count} arguments, found {value}` |
| `starts here` / `ends here` | delimiting a construct in recovery diagnostics | `block starts here` |
| `was expanded from` | generated or expanded source | `{what} '{sym}' was expanded from this call` |

### Banned synonyms

These say nothing the table does not already say, and splitting one relation across several
spellings is what makes a diagnostic catalog sound assembled by committee.

| Do not write | Write |
| --- | --- |
| `requires`, `expects`, `demands`, `wants` | `needs` |
| `allows`, `permits` | `accepts` |
| `lacks`, `does not have` | `has no` |
| `is duplicated`, `is repeated` | `already` |
| `is incompatible with` | `conflicts with` |
| `is unsupported` | `does not support`, with the actor named |

Extend the table only when a genuinely new relation appears, and extend it in this file at the same
time. A verb that exists in the catalog but not here is drift, not vocabulary.

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
- Does every relation use the verb the table gives it, with no synonym slipped in?
- Are both sides of every disagreement visible?
- Does each note add provenance or a distinct fact?
- Is every help line executable advice?
- Are spans minimal and sufficient?
- Can any clause be removed without losing information?
- Did every placeholder, constraint, and recovery path survive the edit?
