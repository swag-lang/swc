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
    stream:        File.FileStream
    fileSize:      u64
    windowStart:   u64
    window:        Array'u8
    readFailed:    bool
    failureReason: String
    reportFailure: (func||(string))?
}

impl HexDocument
{
    mtd failRead(reason: string)
    {
        if .readFailed do
            return
        .failureReason = reason
        if .failureReason.isEmpty() do
            .failureReason = "file stream could not be read"
        .readFailed = true
        if .reportFailure do
            .reportFailure!(.failureReason.toString())
    }

    // Opens `fileName` for reading and reports whether its size could be established.
    mtd open(fileName: string)->bool
    {
        .close()

        .stream = catch File.openRead(fileName) as openError
        if openError != null
        {
            .failRead(Errors.message(openError))
            return false
        }

        let size = catch .stream.size() as sizeError
        if sizeError != null
        {
            .failRead(Errors.message(sizeError))
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
        .failureReason.clear()
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
        catch .stream.seek(.Begin, start) as seekError
        if seekError != null
        {
            .failRead(Errors.message(seekError))
            .window.clear()
            return false
        }

        let read = catch .stream.read(.window.toSlice()) as readError
        if readError != null
        {
            .failRead(Errors.message(readError))
            .window.clear()
            return false
        }

        if read < wanted
        {
            .failRead("file ends before its reported size")
            .window.clear()
            return false
        }

        .window.resize(read)
        .windowStart = start
        return true
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
        catch .stream.seek(.Begin, offset) as seekError
        if seekError != null
        {
            .failRead(Errors.message(seekError))
            result.clear()
            return result
        }

        let read = catch .stream.read(result.toSlice()) as readError
        if readError != null
        {
            .failRead(Errors.message(readError))
            result.clear()
            return result
        }

        if read < wanted
        {
            .failRead("file ends before its reported size")
            result.clear()
            return result
        }

        result.resize(read)
        return result
    }
}
