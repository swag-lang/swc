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

enum HexAnalysisStringKind
{
    Ascii
    Utf16Little
    Utf16Big
}

struct HexAnalysisRange
{
    offset: u64
    length: u64
}

// One inferred readable run and the exact bytes that produced it.
struct HexAnalysisString
{
    offset: u64
    length: u64
    kind:   HexAnalysisStringKind
    text:   String
}

// Bounded findings for one explicit file range.
struct HexAnalysisResult
{
    range:            HexAnalysisRange
    scanned:          u64
    histogram:        [256] u64
    zeroCount:        u64
    printableCount:   u64
    entropy:          f64
    strings:          Array'HexAnalysisString
    stringsTruncated: bool
    cancelled:        bool
    failureReason:    String
}

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
        if !.units do
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
                var text = String.from(Swag.makeString(.preview.buffer, .preview.count))
                if .units > .preview.count do
                    text += "..."
                var entry = HexAnalysisString{offset: .start, length: .length, kind: kind}
                entry.text = #move text
                result.strings.add(#move entry)
            }
            else do
                result.stringsTruncated = true
        }

        .reset()
    }
}

private func scanHexAnalysisByte(result: *HexAnalysisResult, ascii: *HexStringScanner, value: u8, offset: u64)
{
    result.histogram[value] += 1
    if value == 0 do
        result.zeroCount += 1

    if isHexPrintable(value)
    {
        result.printableCount += 1
        ascii.append(offset, 1, value)
    }
    else do
        ascii.flush(.Ascii, result)
}

private func scanHexAnalysisPair(result: *HexAnalysisResult, little, big: *HexStringScanner, first, second: u8, offset: u64)
{
    if isHexPrintable(first) and second == 0 do
        little.append(offset, 2, first)
    else do
        little.flush(.Utf16Little, result)

    if first == 0 and isHexPrintable(second) do
        big.append(offset, 2, second)
    else do
        big.flush(.Utf16Big, result)
}

private func finishHexAnalysis(result: *HexAnalysisResult, ascii: *HexStringScanner, little, big: *[2] HexStringScanner)
{
    ascii.flush(.Ascii, result)
    for index in 2
    {
        little[][index].flush(.Utf16Little, result)
        big[][index].flush(.Utf16Big, result)
    }

    result.strings.sort(func(a, b) { return a.offset <=> b.offset })

    if !result.scanned do
        return
    for count in result.histogram where count
    {
        let share = cast(f64) count / cast(f64) result.scanned
        result.entropy -= share * Math.log2(share)
    }
}

// Streams one range into fixed byte counts and a bounded set of inferred ASCII and UTF-16 runs.
// `cancelled` and `processed` are optional atomics owned by an asynchronous caller.
func analyzeHexRange(fileName: string, range: HexAnalysisRange, cancelled: #null *u32 = null, processed: #null *u64 = null)->HexAnalysisResult
{
    var result: retval
    result.range = range
    if !range.length do
        return result
    if cancelled and Atomic.get(cancelled!)
    {
        result.cancelled = true
        return result
    }

    var stream = catch File.openRead(fileName) as openError
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
        if cancelled and Atomic.get(cancelled!)
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

        if !count
        {
            result.failureReason = hexStrings().err_AnalysisShortRead
            break
        }

        bytes.resize(count)
        for value in bytes
        {
            let offset = range.offset + result.scanned
            scanHexAnalysisByte(&result, &ascii, value, offset)
            if hasPrevious
            {
                let pairOffset = offset - 1
                let parity     = cast(u64) (pairOffset & 1)
                scanHexAnalysisPair(&result, &little[parity], &big[parity], previous, value, pairOffset)
            }

            previous       = value
            hasPrevious    = true
            result.scanned += 1
        }

        if processed do
            Atomic.exchange(processed!, result.scanned)
        remaining -= count
    }

    finishHexAnalysis(&result, &ascii, &little, &big)
    return result
}

// Owns one cancellable analysis whose worker borrows this value until completion.
struct HexAnalysisOperation
{
    job:             Jobs.Job
    fileName:        String
    range:           HexAnalysisRange
    result:          HexAnalysisResult
    cancelRequested: u32
    processed:       u64
    started:         bool
}

impl HexAnalysisOperation
{
    mtd start(fileName: string, range: HexAnalysisRange)
    {
        Debug.assert(!.started)
        .fileName = fileName
        .range    = range
        .result   = {}
        Atomic.exchange(&.cancelRequested, 0)
        Atomic.exchange(&.processed, 0)
        .job.lambda = func(data: #null *void)
        {
            let operation = cast(*HexAnalysisOperation) data!
            operation.result = analyzeHexRange(operation.fileName.toString(), operation.range, &operation.cancelRequested, &operation.processed)
        }
        .job.data = me
        .started  = true
        Jobs.schedule(&.job)
    }

    mtd cancel()
    {
        if .started do
            Atomic.exchange(&.cancelRequested, 1)
    }

    mtd const isDone()->bool => .started and Jobs.isDone(&.job)

    mtd progress()->u64 => Atomic.get(&.processed)

    mtd finish()->HexAnalysisResult
    {
        Debug.assert(.isDone())
        Jobs.wait(&.job)
        .started = false
        return #move .result
    }

    // Cancels active work and reports when this borrowed operation can be destroyed.
    mtd retire()->bool
    {
        if !.started do
            return true
        .cancel()
        if !.isDone() do
            return false
        Jobs.wait(&.job)
        .started = false
        return true
    }

    mtd opDrop()
    {
        if .started
        {
            .cancel()
            Jobs.wait(&.job)
        }
    }
}
