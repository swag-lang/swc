# Swag user-facing messages

Swag speaks with calm confidence: concise on the surface, exact underneath, and never vague about what stopped or why. The compiler is direct without sounding cold, clever without making jokes, and helpful without lecturing.

This convention covers every English text emitted for a user: diagnostics, span labels, notes, help, command descriptions, progress lines, statistics, dry-run output, crash reports, runtime safety messages, and developer validation output. Machine protocols, encoded symbol names, source-language keywords, and third-party text keep their required spelling.

## Voice

- Name the actor and the broken contract: `array access provides 3 indices, but the array needs 2`
- Prefer exact verbs: `needs`, `does not accept`, `does not fit`, `cannot resolve`, `stops here`, `originates here`
- Avoid blanket labels such as `invalid`, `unexpected`, `failed`, `wrong`, `type mismatch`, or `not viable` when the compiler knows the actual disagreement
- Never joke, apologize, blame the programmer, or add conversational filler
- Keep one idea in the primary message; move origin, prior decisions, and actionable repair to notes or help
- Use contractions nowhere

## Shape

Diagnostics start with lowercase text unless a source token, placeholder, or technical acronym leads the sentence. They have no terminal punctuation.

Use the diagnostic levels as a narrative:

1. `error` or `warning` states the contract that does not hold
2. `note` answers where the contract or conflicting fact originates
3. `help` gives a concrete action only when one is known

Embed catalog help as `; [help] <imperative action>`. Do not repeat the primary message in a note, and do not add help that merely restates a language rule.

Command descriptions start with an action verb, preserve every condition and side effect, and omit terminal punctuation. Status tables use short noun labels and lowercase state values.

## Information contract

Before rewriting a message, preserve:

- every dynamic placeholder and its meaning
- the operation that stopped
- actual and required values, types, counts, ranges, or candidates
- constraints, defaults, exclusions, side effects, and platform limits
- source and generated-source provenance
- every actionable recovery path

Keep underlines on the smallest source range that proves the primary statement. Add a secondary span only when it answers a different question. For generated code, show the generated failure first, then the expansion chain; keep the call site and root available without flooding the report.

## High-value diagnostics

For overloads and generics, state the decision path instead of dumping candidates:

```text
error: cannot deduce generic parameter 'T': argument 2 has type 'string', but argument 1 previously deduced 's32'
note: candidate 'map(func(T) T, []T)' stops here: parameter 'fn' needs 'func(s32) s32', but argument 2 has type 'func(string) string'
help: make the argument types agree, or specify 'T' explicitly
```

For macros, mixins, `#ast`, and generated source, distinguish user code from generated code and identify the expansion origin. Do not expose compiler implementation detail unless the compiler itself broke an invariant.

For internal compiler failures, say which phase stops and include the precise invariant or unavailable artifact. Use `internal compiler error` only for compiler defects, never for source errors.

## Review checklist

- Can an experienced programmer understand the broken contract from the first line?
- Are both sides of every disagreement visible?
- Does each note add provenance or a distinct fact?
- Is every help line executable advice?
- Are spans minimal and sufficient?
- Can any clause be removed without losing information?
- Did every placeholder, constraint, and recovery path survive the edit?
