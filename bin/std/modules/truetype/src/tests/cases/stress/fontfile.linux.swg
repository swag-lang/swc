#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test

using Swag, Core

// Positional reads preserve both byte order and the shared descriptor's cursor.
#[Swag.TestTag("stress")]
#test
{
    const BlockSize = 64'u64 * 1024
    const Blocks    = 145'u64
    const Start     = 37'u64
    var original: Array'u8
    original.resize(Blocks * BlockSize + 13)
    let originalBytes = unwrap original.buffer
    for block in Blocks do
        Memory.set(originalBytes + block * BlockSize, cast(u8, block), BlockSize)
    Memory.set(originalBytes + Blocks * BlockSize, 237, 13)

    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("swag-font-range-%.bin", Guid128.random().toString()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, original.toSlice())
    var stream = expect File.openRead(path)
    expect stream.seek(.Begin, 11)

    var destination: Array'u8
    destination.resize(original.count)
    let complete = expect readParallelFontRange(&stream, 0, destination.toSlice(), 4)
    Swag.require(complete.ok and complete.count == original.count)
    Swag.require(Slice.equals(original.toSlice(), destination.toSlice()))

    let partial = expect readParallelFontRange(&stream, Start, destination.toSlice(), 4)
    Swag.require(partial.ok and partial.count == original.count - Start)
    Swag.require(Slice.equals(original.toSlice()[Start to], destination.toSlice()[0 until partial.count]))
    destination.resize(original.count + 101)
    let short = expect readParallelFontRange(&stream, 0, destination.toSlice(), 4)
    Swag.require(short.ok and short.count == original.count)
    Swag.require(Slice.equals(original.toSlice(), destination.toSlice()[0 until short.count]))
    Swag.require(expect stream.position() == 11)

    let snapshot = expect FontSource.loadFile(path)
    Swag.require(Slice.equals(original.toSlice(), snapshot.bytes()))
}
