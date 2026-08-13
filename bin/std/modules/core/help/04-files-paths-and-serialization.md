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

## Memory-mapped files

[[Core.File.MappedFile]] creates independently owned [[Core.File.MappedRegion]]
views for random access to large files. A region may start at any byte offset;
the platform alignment is handled internally.

```swag
using Core

var file   = try File.MappedFile.open("archive.bin", .ReadWrite)
var header = try file.map(0, 4096)
header.writableBytes()[0] = 1
try header.flush()
```

Close all regions before resizing. A region remains usable if its source
[[Core.File.MappedFile]] is closed, but its byte slices become invalid as soon
as the region itself closes. `CopyOnWrite` regions are writable private copies;
their changes are intentionally never persisted.

## Watching a directory

[[Core.Directory.Watcher]] provides a cancellable stream for tools that react
to file edits. Each read has an explicit [[Core.Directory.WatchStatus]]:
changes, timeout, overflow, or cancellation.

```swag
using Core

var options: Directory.WatchOptions
options.recurse = true
var watcher = try Directory.watch("sources", options)

for
{
    let batch = try watcher.next(1000)
    if batch.status == .Overflow
    {
        // Rescan the complete tree because native records were lost.
        continue
    }
    if batch.status == .Cancelled do
        break
    for change in batch.changes do
        Log.write(change.path)
}
```

Rename records are paired even when a host buffer boundary splits them. A
timeout leaves the native request pending, so repeated timed reads do not create
a notification gap. Call `cancel` from another thread to wake an unbounded
`next`; call `close` only after the reading thread has returned.

## Structured data

[[Core.Serialization]] provides a shared traversal model with JSON, XML, and
tagged-binary readers and writers. The read side reports malformed input through
`fail`; the write side serializes values according to their reflected fields and
serialization attributes.

Treat external input as untrusted. Keep parsing errors at the boundary, add the
filename or protocol context there, and only pass validated values into the rest
of the program.
