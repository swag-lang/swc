# Files, paths, and serialization

[[Core.Path]] manipulates path text without accessing the filesystem.
[[Core.File]] and [[Core.Directory]] perform filesystem operations.
[[Core.File.FileStream]], [[Core.ByteStream]], [[Core.ByteSource]], [[Core.ByteSink]], and
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

`File.readAllText` and `File.writeAllText` use UTF-8 by default. Their encoding
overloads accept [[Core.Text.Encoding]]; reading skips a matching byte-order
mark, while writing can add one. Explicit decoding replaces malformed sequences
with the Unicode replacement character. Writing encodes the complete text
before opening the destination, so unrepresentable text does not truncate an
existing file.

## Decoding a file of any size

[[Core.ByteSource]] and [[Core.ByteSink]] are what a codec reads and writes through. Each has a
file backing and a memory backing behind the same operations, so a decoder written once reads a
ten-hour recording and a byte slice alike, and a file source holds one read window whatever the
length of the file. A read larger than the window goes straight to its destination;
[[Core.ByteSource.peek]] lends the bytes ahead of the read position without copying them, which
is how a walker over frame headers scans a file at the cost of its index.

```swag
using Core

var source = try ByteSource.openFile("recording.mp3")
while not source.isAtEnd()
{
    let header = try source.peek(4)
    let length = frameLength(header)
    try source.skip(length)
}
```

A container writer reserves the totals of its header and fills them in once the last frame has
landed: [[Core.ByteSink.patch]] rewrites bytes the sink already accepted, so writing a long
stream costs the memory of one frame rather than the memory of the result.

```swag
using Core

var sink = try ByteSink.createFile("clip.avi")
let sizeField = sink.position()
try sink.writeLittleEndian(0'u32)
// ... frames ...
try sink.patch(sizeField, sizeBytes)
try sink.close()
```

`ByteSink.position()` is the logical offset accepted by the sink. If file I/O fails, the file may
contain only part of that stream; the sink closes itself, later writes, patches, and flushes fail,
and `close()` only releases the failed sink without retrying pending bytes. Treat the destination as
incomplete after such an error.

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
        Console.println(change.path)
}
```

Rename records are paired even when a host buffer boundary splits them. A
timeout leaves the native request pending, so repeated timed reads do not create
a notification gap. Call `cancel` from another thread to wake an unbounded
`next`; call `close` only after the reading thread has returned.

## Structured data

[[Core.Serialization]] provides a shared traversal model with JSON, XML, and
tagged-binary readers and writers. JSON is declaration-driven and accepts reordered,
missing, and unknown properties for forward-compatible interchange. The read side
reports malformed input through `fail`; the write side serializes values according
to their reflected fields and serialization attributes. XML writes a `<root>` document
with fields in declaration order and source field names. It writes Boolean and numeric
sequences as space-separated text and escapes XML entities in [[Core.String]] values.
Shapes the XML reader cannot delimit fail with `UnsupportedFormatError` instead of
returning partial output. Carriage returns use a numeric character reference so a
write/read round trip preserves them despite XML line-ending normalization.

Write a value with the declaration-driven XML writer:

```swag
using Core

struct Status
{
    ready: bool
    count: u32
}

var output: ConcatBuffer
var encoder: Serialization.Encoder'Serialization.Write.Xml
try encoder.writeAll(&output, Status{true, 3})
let xml = output.toString()
```

TagBin stores one readable document schema in the root header and one readable key
for every reflected field. Declare [[Core.Serialization.Schema]] on persisted root
types and keep that value stable across type or module renames. Declare
[[Core.Serialization.Key]] before renaming a persisted field; the source identifier
can then change while its single wire identity remains unchanged. Concrete structs
stored through an interface always need a [[Core.Serialization.TypeKey]], because
their source type name is never used as a fallback identity.

```swag
#[Serialization.Schema("example.settings")]
struct Settings
{
    #[Serialization.Key("theme")]
    selectedTheme: String
}
```

Keys are canonical rather than aliases: a field or struct type accepts one identity,
and stored documents should be rewritten deliberately when that identity changes.

Treat external input as untrusted. Keep parsing errors at the boundary, add the
filename or protocol context there, and only pass validated values into the rest
of the program.
