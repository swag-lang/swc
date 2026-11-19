# Swag Scope JSON Viewer Backlog

This backlog covers the planned read-only structural viewer for JSON and JSON Lines.

### app.scope.json.001 — JSON and JSON Lines have no semantic reader

- Evidence: `.json` opens in the Code viewer and `.jsonl` has no registered semantic surface, so
  objects and arrays cannot be explored as a tree, properties cannot be addressed by JSON Pointer,
  duplicate keys and malformed ranges are not summarized, and schema-derived meaning is absent.
- Next: build a bounded JSON token/range index and a synchronized virtual tree/source view, starting
  with strict JSON and independently streamed JSON Lines before adding optional local schemas.
- Done when: tree nodes retain exact source byte ranges and original number/string spelling;
  filter and JSON Pointer jump in both directions; malformed input publishes every safe partial
  result plus precise damage; huge arrays and JSON Lines remain paged; search covers keys and values;
  and schemas are local or explicitly supplied rather than fetched from the network.
- Related: app.scope.text.004, app.scope.viewers.004, app.scope.viewers.006
