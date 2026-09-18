#global internal

using Core

// One analysis pass reads this many bytes before publishing cancellation progress. The buffer is
// large enough for sequential I/O and small enough that stopping never waits on a resident file.
const HexAnalysisChunkSize = 256 * 1024'u64

// String inference is intentionally bounded: the first findings stay useful on a damaged or
// repetitive image without letting a synthetic file turn an inspection panel into the file.
const HexAnalysisStringLimit       = 4096'u64
const HexAnalysisStringPreview     = 192'u64
const HexAnalysisMinimumStringSize = 4'u64

// Encoding an inferred string was read in.
enum HexAnalysisStringKind
{
    Ascii           // Each character is one printable byte.
    Utf16Little     // Each character is a printable byte followed by a zero byte.
    Utf16Big        // Each character is a zero byte followed by a printable byte.
}

// Bytes one analysis covers.
struct HexAnalysisRange
{
    offset: u64
    length: u64
}

// One inferred readable run and the exact bytes that produced it.
struct HexAnalysisString
{
    offset: u64                       // First byte of the run in the file.
    length: u64                       // Bytes the run covers, two per character in UTF-16.
    kind:   HexAnalysisStringKind
    text:   String                    // Readable preview, ending in `...` when the run is longer.
}

// Bounded findings for one explicit file range.
struct HexAnalysisResult
{
    range:            HexAnalysisRange
    scanned:          u64                         // Bytes read before completion, cancellation, or failure.
    histogram:        [256] u64                   // Occurrences of each byte value.
    zeroCount:        u64
    printableCount:   u64                         // Bytes the text column shows as themselves.
    entropy:          f64                         // Shannon entropy of the scanned bytes, in bits per byte.
    strings:          Array'HexAnalysisString     // Inferred runs in file order, at most `HexAnalysisStringLimit`.
    stringsTruncated: bool                        // Whether more runs were found than `strings` keeps.
    cancelled:        bool
    failureReason:    String                      // Empty unless the file could not be read.
}

// Readable run being accumulated in one encoding, flushed when a byte breaks it.
private struct HexStringScanner
{
    start:   u64
    length:  u64
    units:   u64
    preview: Array'u8
}

private impl HexStringScanner
{
    mtd reset()
    {
        .start  = 0
        .length = 0
        .units  = 0
        .preview.clear()
    }

    mtd append(offset, byteLength: u64, value: u8)
    {
        if not .units do
            .start = offset
        .length += byteLength
        .units  += 1
        if .preview.count < HexAnalysisStringPreview do
            .preview.add(value)
    }

    mtd flush(kind: HexAnalysisStringKind, result: *HexAnalysisResult)
    {
        if .units >= HexAnalysisMinimumStringSize
        {
            if result.strings.count < HexAnalysisStringLimit
            {
                var entry = HexAnalysisString{offset: .start, length: .length, kind: kind}
                entry.text = String.from(cast(string) .preview.toSlice())
                if .units > .preview.count do
                    entry.text += "..."
                result.strings.add(#move entry)
            }
            else do
                result.stringsTruncated = true
        }

        .reset()
    }
}

private impl HexAnalysisResult
{
    // Counts the byte at `offset` and extends or closes the ASCII run.
    mtd scanByte(ascii: *HexStringScanner, value: u8, offset: u64)
    {
        .histogram[value] += 1
        if value == 0 do
            .zeroCount += 1

        if isHexPrintable(value)
        {
            .printableCount += 1
            ascii.append(offset, 1, value)
        }
        else do
            ascii.flush(.Ascii, me)
    }

    // Extends or closes the UTF-16 runs with the byte pair `first`, `second` at `offset`.
    mtd scanPair(little, big: *HexStringScanner, first, second: u8, offset: u64)
    {
        if isHexPrintable(first) and second == 0 do
            little.append(offset, 2, first)
        else do
            little.flush(.Utf16Little, me)

        if first == 0 and isHexPrintable(second) do
            big.append(offset, 2, second)
        else do
            big.flush(.Utf16Big, me)
    }

    // Closes every open run, orders the strings by offset, and derives the entropy.
    mtd finishScan(ascii: *HexStringScanner, little, big: *[2] HexStringScanner)
    {
        ascii.flush(.Ascii, me)
        for index in 2
        {
            little[][index].flush(.Utf16Little, me)
            big[][index].flush(.Utf16Big, me)
        }

        .strings.sort(func(a, b) => a.offset <=> b.offset)

        if not .scanned do
            return
        for count in .histogram where count
        {
            let share = cast(f64) count / cast(f64) .scanned
            .entropy -= share * Math.log2(share)
        }
    }
}

// Returns the byte counts, entropy, and a bounded set of inferred ASCII and UTF-16 runs of `range` in `fileName`.
//
// The range is streamed in `HexAnalysisChunkSize` chunks. `cancelled` and `processed` are optional
// atomics owned by an asynchronous caller: a non-zero `cancelled` stops the scan, and `processed`
// follows the bytes scanned so far. A failure is reported in `failureReason`, never as an error.
func analyzeHexRange(fileName: string, range: HexAnalysisRange, cancelled: *u32? = null, processed: *u64? = null)->HexAnalysisResult
{
    var result: retval
    result.range = range
    if not range.length do
        return result
    if cancelled and Atomic.get(cancelled)
    {
        result.cancelled = true
        return result
    }

    var stream = catch File.openReadLive(fileName) as openError
    if openError != null
    {
        result.failureReason = Errors.message(openError)
        return result
    }

    defer stream.close()

    catch stream.seek(.Begin, range.offset) as seekError
    if seekError != null
    {
        result.failureReason = Errors.message(seekError)
        return result
    }

    var ascii:       HexStringScanner
    var little:      [2] HexStringScanner
    var big:         [2] HexStringScanner
    var previous:    u8
    var hasPrevious: bool
    var bytes:       Array'u8
    var remaining = range.length
    while remaining
    {
        if cancelled and Atomic.get(cancelled)
        {
            result.cancelled = true
            break
        }

        let wanted = Math.min(remaining, HexAnalysisChunkSize)
        bytes.resize(wanted)
        let count = catch stream.read(bytes.toSlice()) as readError
        if readError != null
        {
            result.failureReason = Errors.message(readError)
            break
        }

        if not count
        {
            result.failureReason = hexStrings().err_AnalysisShortRead
            break
        }

        bytes.resize(count)
        for value in bytes
        {
            let offset = range.offset + result.scanned
            result.scanByte(&ascii, value, offset)
            if hasPrevious
            {
                let pairOffset = offset - 1
                let parity     = cast(u64) (pairOffset & 1)
                result.scanPair(&little[parity], &big[parity], previous, value, pairOffset)
            }

            previous       = value
            hasPrevious    = true
            result.scanned += 1
        }

        if processed do
            Atomic.exchange(processed, result.scanned)
        remaining -= count
    }

    result.finishScan(&ascii, &little, &big)
    return result
}

// Owns one cancellable analysis whose worker borrows this value until completion.
struct HexAnalysisOperation
{
    task:            Swag.Task
    fileName:        String
    range:           HexAnalysisRange
    result:          HexAnalysisResult
    cancelRequested: u32
    processed:       u64
    started:         bool
}

impl HexAnalysisOperation
{
    // Starts analyzing `range` of `fileName` on a worker task.
    //
    // The operation must not be started already: the previous result has to be collected with
    // [[HexAnalysisOperation.finish]] or discarded by [[HexAnalysisOperation.retire]] first.
    mtd start(fileName: string, range: HexAnalysisRange)
    {
        Swag.assert(not .started)
        .fileName = fileName
        .range    = range
        .result   = {}
        Atomic.exchange(&.cancelRequested, 0)
        Atomic.exchange(&.processed, 0)
        .started = true

        .task.submit(func|operation = me|()
        {
            operation.result = analyzeHexRange(operation.fileName.toString(), operation.range, &operation.cancelRequested, &operation.processed)
        })
    }

    // Asks a running analysis to stop; the partial result is still collected by [[HexAnalysisOperation.finish]].
    mtd cancel()
    {
        if .started do
            Atomic.exchange(&.cancelRequested, 1)
    }

    mtd const isDone()->bool => .started and .task.isDone()

    mtd progress()->u64 => Atomic.get(&.processed)

    // Returns the result of a finished analysis, and makes the operation ready to start again.
    mtd finish()->HexAnalysisResult
    {
        Swag.assert(.isDone())
        .task.wait()
        .started = false
        return #move .result
    }

    // Cancels active work, and reports whether the worker has let go of this operation so it can be destroyed.
    mtd retire()->bool
    {
        if not .started do
            return true
        .cancel()
        if not .isDone() do
            return false
        .task.wait()
        .started = false
        return true
    }

    mtd opDrop()
    {
        if .started
        {
            .cancel()
            .task.wait()
        }
    }
}
