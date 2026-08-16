#global internal

using Core

// Bytes the viewer keeps resident at once. One window covers many screens, so a reader moving
// through a file crosses a read every few hundred rows rather than on every scroll notch.
const HexWindowSize = 256 * 1024'u64

// Reads start on this boundary, so scrolling back by one row lands on the block that was already
// read instead of on a window shifted by sixteen bytes.
const HexWindowAlign = 64 * 1024'u64

// File the viewer reads through, one bounded window at a time.
//
// Nothing here ever holds the whole file. [[HexDocument.ensure]] moves a window of at most
// `HexWindowSize` bytes over the region being displayed, and [[HexDocument.read]] serves a bounded
// copy without disturbing that window, so a ten-gigabyte file costs exactly what a small one does.
struct HexDocument
{
    stream:      File.FileStream
    fileSize:    u64
    windowStart: u64
    window:      Array'u8
    readFailed:  bool
}

impl HexDocument
{
    // Opens `fileName` for reading and reports whether its size could be established.
    mtd open(fileName: string)->bool
    {
        .close()

        .stream = catch File.openRead(fileName) as openError
        if openError != null
        {
            .readFailed = true
            return false
        }

        let size = catch .stream.size() as sizeError
        if sizeError != null
        {
            .readFailed = true
            .stream.close()
            return false
        }

        .fileSize = size
        return true
    }

    mtd close()
    {
        .stream.close()
        .window.clear()
        .windowStart = 0
        .readFailed  = false
    }

    // Returns whether `offset` currently sits inside the resident window.
    mtd isResident(offset: u64)->bool
    {
        return offset >= .windowStart and offset - .windowStart < .window.count
    }

    // Makes `[offset, offset + length)` resident, and reports whether it now is.
    //
    // A request wider than `HexWindowSize` is served only up to the window; the viewer never asks
    // for more than one screen of bytes, which is what keeps that bound invisible.
    mtd ensure(offset, length: u64)->bool
    {
        if .readFailed or !.stream.isOpen() do
            return false
        if offset >= .fileSize do
            return length == 0
        let end = Math.min(offset + length, .fileSize)
        if offset >= .windowStart and end <= .windowStart + .window.count do
            return true

        let start  = offset / HexWindowAlign * HexWindowAlign
        let wanted = Math.min(HexWindowSize, .fileSize - start)
        .window.resize(wanted)
        discard catch .stream.seek(.Begin, start)

        let read = catch .stream.read(.window.toSlice()) as readError
        if readError != null
        {
            .readFailed = true
            .window.clear()
            return false
        }

        .window.resize(read)
        .windowStart = start
        return end <= start + read
    }

    // Returns the byte at `offset`, or zero when it is outside the resident window.
    //
    // Painting calls this once per drawn byte, so it stays a bounds test and an index; the caller
    // establishes residency once for the whole row range through [[HexDocument.ensure]].
    mtd byteAt(offset: u64)->u8
    {
        if offset < .windowStart do
            return 0
        let index = offset - .windowStart
        if index >= .window.count do
            return 0
        return .window[index]
    }

    // Returns a copy of `[offset, offset + count)`, leaving the resident window in place.
    //
    // This is how the clipboard and the value inspector reach bytes: both need a range the display
    // window does not necessarily hold, and neither may disturb what is on screen.
    mtd read(offset, count: u64)->Array'u8
    {
        var result: retval
        if .readFailed or !.stream.isOpen() or !count or offset >= .fileSize do
            return result

        let wanted = Math.min(count, .fileSize - offset)
        result.resize(wanted)
        discard catch .stream.seek(.Begin, offset)

        let read = catch .stream.read(result.toSlice()) as readError
        if readError != null
        {
            result.clear()
            return result
        }

        result.resize(read)
        return result
    }
}
