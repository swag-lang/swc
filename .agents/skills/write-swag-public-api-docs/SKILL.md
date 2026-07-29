---
name: write-swag-public-api-docs
description: Write and review documentation comments for public Swag APIs under bin/, including runtime and standard modules, module overviews, examples and reference prose, Swag.NoDoc exclusions, symbol links, and supported Markdown. Use whenever adding or changing public declarations or documentation comments in bin/runtime, bin/std, or another documented bin workspace.
---

# Write Swag Public API Docs

Treat documentation as a product, not as an annotated symbol dump. Keep precise contracts next to declarations, and put workflow-oriented prose in the module's editorial layer.

## Build the documentation in layers

Use the narrowest layer that fits the content:

1. `module.swg` is the front page. Its leading comment states the module's purpose, shared conventions, one first-use example, and the most important failure or ownership rule.
2. `help/*.md` contains task-oriented guides beside `src/`. Files are rendered in lexical path order inside the API page. Start each file with one `# Title`; the generator uses it as the guide title and table-of-contents entry.
3. Source comments state the exact contract of one public symbol or member. Keep implementation history, broad tutorials, and repeated module conventions out of them.

Prefer a small set of durable guides organized by user goals: getting started, choosing an abstraction, common workflows, integration, and advanced constraints. A guide should link to the reference instead of copying signatures or exhaustive option lists.

The generated page is a flat reference connected by links. Every method, nested type, enum, constant, and attribute keeps one standalone, qualified entry. Module, namespace, and owner-type tables index those entries; they never replace or nest the canonical symbol documentation. Write summaries that remain useful in those compact tables.

Each namespace also has a standalone index of its child namespaces and directly declared public symbols. A type similarly indexes methods and other public symbols it owns.

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

- Put module overview prose at the top of `module.swg`, before imports and `#run`. Confirm it appears below the module title in the generated page.
- Put longer conceptual and workflow documentation in Markdown files under `help/`, next to `src/`.
- Put `//` comments immediately before namespaces, structs, interfaces, enums, attributes, and functions.
- Put short `//` comments on the same line after enum values, constants, aliases, and public fields when the comment describes only that member.
- For an attributed declaration, put the documentation before the first `#[...]` line so the comment describes the whole declaration rather than an attribute.
- For `using name: struct` or `using name: union` fields, prefer a same-line comment after `struct` or `union`; the aggregate body remains implementation detail.
- Use a leading comment for a member when its contract needs multiple paragraphs, code, a table, or an admonition.
- Make the first comment line a short, complete summary. The generator uses that line alone in API summary tables, so do not wrap it onto another comment line.
- When more detail follows, put one empty `//` line immediately after the summary, then write the long description. For example:

  ```swag
  // Creates a font at the requested draw size.
  //
  // `mode` selects bitmap, MSDF, or automatic rendering.
  func create(...)
  ```

- Write prose and ordinary Markdown, not tag syntax. Do not introduce `@param`, `@return`, `@throws`, or similar keyword inventories.
- Keep authoring content-focused: headings, paragraphs, examples, tables, callouts, and symbol links are enough. Do not invent documentation directives or metadata keywords for prose.

## Describe the contract

- State what the API does before explaining special cases.
- Name units, ranges, coordinate systems, encodings, and defaults when they matter.
- State nullability, ownership, borrowing, lifetime, allocation, and cleanup obligations.
- State observable side effects and how failure is reported.
- Explain non-obvious parameter relationships and return values.
- Avoid restating the declaration or describing private implementation mechanics.
- Use precise, calm English and complete sentences for prose.
- Give every public field and enum value a short contract when its units, meaning, default, range, lifetime, or relationship is not completely obvious.
- Document an enum case by its semantic meaning. The generated case table intentionally omits numeric values; mention the representation only when that number is itself an interoperability contract.
- Mark a public representation `#[Swag.Opaque]` when callers have a real type-level contract but its fields are not API. Document the type and its workflows; the generator omits its fields. Do not repeat that exclusion on every field.
- Put the common contract on the first overload in source order. Add comments to later overloads only for behavior that differs from the common contract.
- Add a runnable `swag` example to the main entry points and workflows of a module. Examples should teach composition, not repeat isolated calls already clear from the signature.

## Use supported markup

- Link every mentioned API type with `[[Full.Type.Name]]`, including types from another module. For example, Pixel can link to `[[Core.Math.Vector2]]`; the generated link targets `std.core.html`.
- Link methods, constants, enum cases, and fields with `[[Full.Symbol.Name]]` when the prose depends on them. Preserve exact spelling and qualify ambiguous names. A current-module prefix is accepted even when the semantic method name omits it.
- Types emitted by generated field tables and declaration signatures are linked automatically when their symbols can be resolved. Never hand-write HTML links around a type to compensate for a generator bug.
- Use backticks or apostrophes around short code tokens, for example `` `null` `` or `'null'`.
- Use fenced `swag` blocks for examples.
- Use standard headings, emphasis, links, images, unordered or ordered lists, description lists, and Markdown tables.
- Use `> NOTE:`, `> TIP:`, `> WARNING:`, `> ATTENTION:`, or `> EXAMPLE:` for callouts.
- Use `<html>...</html>` only when the supported markup cannot express the required layout.
- Keep generated pages static: link only to `.html` documentation pages and never add PHP or script elements.
- In `.Examples` source files, place prose between `/**` and `*/`; keep executable Swag code outside those blocks.

## Validate

1. Run the narrowest relevant `swc doc` command and inspect the generated page.
2. Run `scripts/audit_api_html.py <generated.html> --source-root <repository-root>` from this skill. On Windows use `py -3`; on other systems use the available Python 3 executable. Use `--require-complete` when completing a full-module documentation pass.
   - With `--source-root`, the audit also checks that multi-line symbol comments separate their one-line table summary from the long description with an empty `//` line.
   - The audit reports enum values separately. Review that list, but do not add prose that merely repeats self-explanatory named constants such as color names.
3. Confirm the `module.swg` overview, every intended `help/*.md` guide, the module and namespace summary tables, and owner-type content tables appear. Then confirm representative methods and nested declarations still have standalone, qualified entries at the root of the detailed reference.
4. Check headings, code coloring, tables, callouts, internal links, cross-module type links, runtime links, and source links touched by the change.
5. Confirm generated pages contain no unresolved `[[...]]` references, PHP, script elements, broken anchors, duplicate IDs, or compiler-generated identifiers and use the generated stylesheet.
6. Confirm `#[Swag.NoDoc]` declarations are absent.
7. Run `tools/web.bat dm` when changing shared documentation rules, website configuration, or several documented modules.
