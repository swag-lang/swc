---
name: write-swag-public-api-docs
description: Write and review documentation comments for public Swag APIs under bin/, including runtime and standard modules, module overviews, examples and reference prose, Swag.NoDoc exclusions, symbol links, and supported Markdown. Use whenever adding or changing public declarations or documentation comments in bin/runtime, bin/std, or another documented bin workspace.
---

# Write Swag Public API Docs

Keep documentation next to the public declaration it describes. Treat comments as part of the API contract: update them whenever behavior, ownership, units, defaults, failure modes, or side effects change.

## Document the intended surface

1. Inspect the module's `BuildCfg.genDoc.kind` before editing:
   - `.Api` documents public declarations.
   - `.Examples` renders numbered source files as a guided document.
   - `.Pages` renders one page per source file.
2. Document every new or changed public declaration unless it is deliberately excluded.
3. Add `#[Swag.NoDoc]` only when an API is intentionally public but unsuitable for generated documentation. Never use it to hide missing documentation.
4. Do not add API documentation to private implementation details.
5. Generate the page before a broad documentation pass and inventory the semantic public surface from that page. Do not infer it from `public` tokens alone: whole-file export and `impl` blocks affect the result.
6. Never expose identifiers reserved to compiler-generated declarations, including names beginning with `__`. Fix the generator boundary if one appears; do not work around it in prose.
7. Document an interface method at its interface declaration. Do not duplicate the same contract on each `impl Interface for Type`.

## Place comments consistently

- Put module overview prose at the top of `module.swg`, before imports and `#run`.
- Put `//` comments immediately before namespaces, structs, interfaces, enums, attributes, and functions.
- Put short `//` comments on the same line after enum values, constants, aliases, and public fields when the comment describes only that member.
- For an attributed declaration, put the documentation before the first `#[...]` line so the comment describes the whole declaration rather than an attribute.
- For `using name: struct` or `using name: union` fields, prefer a same-line comment after `struct` or `union`; the aggregate body remains implementation detail.
- Use a leading comment for a member when its contract needs multiple paragraphs, code, a table, or an admonition.
- Keep the summary in the first paragraph. Make it understandable without reading the implementation.
- Write prose and ordinary Markdown, not tag syntax. Do not introduce `@param`, `@return`, `@throws`, or similar keyword inventories.

## Describe the contract

- State what the API does before explaining special cases.
- Name units, ranges, coordinate systems, encodings, and defaults when they matter.
- State nullability, ownership, borrowing, lifetime, allocation, and cleanup obligations.
- State observable side effects and how failure is reported.
- Explain non-obvious parameter relationships and return values.
- Avoid restating the declaration or describing private implementation mechanics.
- Use precise, calm English and complete sentences for prose.
- Give every public field and enum value a short contract when its units, meaning, default, range, lifetime, or relationship is not completely obvious.
- Mark a public representation `#[Swag.Opaque]` when callers have a real type-level contract but its fields are not API. Document the type and its workflows; the generator omits its fields. Do not repeat that exclusion on every field.
- Put the common contract on the first overload in source order. Add comments to later overloads only for behavior that differs from the common contract.
- Add a runnable `swag` example to the main entry points and workflows of a module. Examples should teach composition, not repeat isolated calls already clear from the signature.

## Use supported markup

- Link to a symbol with `[[Full.Symbol.Name]]`. Preserve exact spelling and qualify ambiguous names.
- Use backticks or apostrophes around short code tokens, for example `` `null` `` or `'null'`.
- Use fenced `swag` blocks for examples.
- Use standard headings, emphasis, links, images, unordered or ordered lists, description lists, and Markdown tables.
- Use `> NOTE:`, `> TIP:`, `> WARNING:`, `> ATTENTION:`, or `> EXAMPLE:` for callouts.
- Use `<html>...</html>` only when the supported markup cannot express the required layout.
- Keep generated pages static: link only to `.html` documentation pages and never add PHP or script elements.
- In `.Examples` source files, place prose between `/**` and `*/`; keep executable Swag code outside those blocks.

## Validate

1. Run the narrowest relevant `swc doc` command and inspect the generated page.
2. Run `scripts/audit_api_html.py <generated.html>` from this skill. On Windows use `py -3`; on other systems use the available Python 3 executable. Use `--require-complete` when completing a full-module documentation pass.
   - The audit reports enum values separately. Review that list, but do not add prose that merely repeats self-explanatory named constants such as color names.
3. Check headings, code coloring, tables, callouts, internal links, runtime links, and source links touched by the change.
4. Confirm generated pages contain no PHP, script elements, broken anchors, duplicate IDs, or compiler-generated identifiers and use the generated stylesheet.
5. Confirm `#[Swag.NoDoc]` declarations are absent.
6. Run `tools/web.bat dm` when changing shared documentation rules, website configuration, or several documented modules.
