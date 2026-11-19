# Swag Scope Configuration Viewer Backlog

This backlog covers planned structural inspection of configuration files: typed YAML and
TOML trees and section/key inspection for INI, properties, and environment files.

### app.scope.config.001 — YAML and TOML have no typed configuration reader

- Evidence: YAML and TOML open as colored code. YAML mappings, sequences, anchors, aliases, tags,
  block scalars, multi-document streams, and duplicate keys are not exposed; TOML tables, arrays of
  tables, dotted keys, dates, integers, and spelling diagnostics likewise remain flat text.
- Next: define format-specific parsers behind one synchronized path/tree/source contract, shipping
  TOML before the substantially larger and riskier YAML surface.
- Done when: nodes retain exact spelling and source ranges, paths are searchable and copyable,
  duplicate/conflicting keys and type damage are diagnosed, YAML alias expansion is cycle- and
  budget-safe, schemas are never fetched implicitly, and huge collections remain virtualized.

### app.scope.config.002 — INI, properties, and environment files lack a key/value inspection mode

- Evidence: `.ini`, `.cfg`, `.conf`, `.properties`, and `.env` files are colored as generic code or
  shown as text even though sections, keys, repeated assignments, comments, continuations, quoted
  values, and interpolation spellings carry the useful structure. Secret-looking values can also
  be copied or exposed during a presentation with no masking aid.
- Next: add a conservative key/value reader whose dialect is declared or detected and whose values
  remain exact source, with presentation-only masking disabled by default.
- Done when: sections and keys form a filterable outline, duplicates and malformed records link
  to source, dialect/encoding decisions are visible, masking never changes copy without an explicit
  choice, interpolation is displayed but never evaluated, and no environment variable or external
  file is read to resolve a value.
