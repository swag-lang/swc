# Files, paths, and serialization

[[Core.Path]] manipulates path text without accessing the filesystem.
[[Core.File]] and [[Core.Directory]] perform filesystem operations.
[[Core.File.FileStream]], [[Core.ByteStream]], and
[[Core.File.TextReader]] support incremental I/O.

```swag
using Core

let configPath = Path.combine("config", "application.json")
if File.exists(configPath)
{
    let source = try File.readAllText(configPath)
    // Decode the source at the application boundary.
}
```

Use whole-file helpers for small resources and configuration. Prefer streams for
large files, bounded memory use, or processing that can start before the complete
file is available.

## Structured data

[[Core.Serialization]] provides a shared traversal model with JSON, XML, and
tagged-binary readers and writers. The read side reports malformed input through
`fail`; the write side serializes values according to their reflected fields and
serialization attributes.

Treat external input as untrusted. Keep parsing errors at the boundary, add the
filename or protocol context there, and only pass validated values into the rest
of the program.
