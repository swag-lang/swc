# Text and Unicode

[[Core.String]] owns mutable UTF-8 bytes. A Swag `string` or byte slice can refer
to existing storage without owning it. Use the owning type when text must survive
changes to its source.

The text namespaces separate operations by encoding:

| Encoding or task | API |
|---|---|
| UTF-8 traversal and validation | [[Core.Utf8]] |
| UTF-16 conversion | [[Core.Utf16]] |
| Unicode categories and case mapping | [[Core.Unicode]] |
| Latin-1 classification | [[Core.Latin1]] |
| Numeric and value conversion | [[Core.StrConv]] |
| Placeholder-based formatting | [[Core.Format]] |
| Tokenization | [[Core.Tokenize]] |
| Regular expressions | [[Core.Parser.RegExp]] |

Indexing UTF-8 by byte is appropriate for ASCII delimiters and encoded storage,
but not for counting displayed characters. Decode runes when character boundaries
matter, and keep byte offsets when slicing the original UTF-8 value.

Formatting creates text for display; parsing converts text back to typed values.
Keep machine-readable formats independent of locale unless a declaration
explicitly accepts globalization settings.
