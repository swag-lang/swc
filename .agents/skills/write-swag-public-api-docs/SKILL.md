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

## Place comments consistently

- Put module overview prose at the top of `module.swg`, before imports and `#run`.
- Put `//` comments immediately before namespaces, structs, interfaces, enums, attributes, and functions.
- Put short `//` comments on the same line after enum values, constants, aliases, and public fields when the comment describes only that member.
- Use a leading comment for a member when its contract needs multiple paragraphs, code, a table, or an admonition.
- Keep the summary in the first paragraph. Make it understandable without reading the implementation.

## Describe the contract

- State what the API does before explaining special cases.
- Name units, ranges, coordinate systems, encodings, and defaults when they matter.
- State nullability, ownership, borrowing, lifetime, allocation, and cleanup obligations.
- State observable side effects and how failure is reported.
- Explain non-obvious parameter relationships and return values.
- Avoid restating the declaration or describing private implementation mechanics.
- Use precise, calm English and complete sentences for prose.

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
2. Check headings, code coloring, tables, callouts, internal links, runtime links, and source links touched by the change.
3. Confirm generated pages contain no PHP or script elements and use the generated stylesheet.
4. Confirm `#[Swag.NoDoc]` declarations are absent.
5. Run `tools/web.bat dm` when changing shared documentation rules, website configuration, or several documented modules.
