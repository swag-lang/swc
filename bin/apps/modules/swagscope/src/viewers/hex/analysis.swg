#global internal
#global namespace Viewers.Hex

using Core

// One analysis pass reads this many bytes before publishing cancellation progress. The buffer is
// large enough for sequential I/O and small enough that stopping never waits on a resident file.
const AnalysisChunkSize = 256 * 1024'u64

// String inference is intentionally bounded: the first findings stay useful on a damaged or
// repetitive image without letting a synthetic file turn an inspection panel into the file.
const AnalysisStringLimit       = 4096'u64
const AnalysisStringPreview     = 192'u64
const AnalysisMinimumStringSize = 4'u64
const AnalysisEntropyBlockMinimum = 64 * 1024'u64
const AnalysisEntropyBlockLimit   = 256'u64
const AnalysisRepeatedBlockSize   = 64 * 1024'u64
const AnalysisRepeatRepresentativeLimit = 256'u64
const AnalysisRepeatedPairLimit         = 256'u64
const AnalysisRepeatBucketCount         = 512'u64

// Encoding an inferred string was read in.
enum AnalysisStringKind
{
    Ascii           // Each character is one printable byte.
    Utf16Little     // Each character is a printable byte followed by a zero byte.
    Utf16Big        // Each character is a zero byte followed by a printable byte.
}

// Bytes one analysis covers.
struct AnalysisRange
{
    offset: u64
    length: u64
}

// One bounded entropy sample and the exact byte range used to calculate it.
struct AnalysisEntropyBlock
{
    range:   AnalysisRange
    entropy: f64
}

// One exact match between two complete fixed-size blocks in the analyzed range.
struct AnalysisRepeatedBlock
{
    firstOffset:    u64
    repeatedOffset: u64
    length:         u64
}

// First retained block for one fingerprint. Bytes verify equality after the hash lookup.
private struct AnalysisRepeatRepresentative
{
    fingerprint: u32
    offset:      u64
    next:        u16
    bytes:       Array'u8
}

// Bounded exact duplicate detector. The hash table narrows candidates; retained block bytes
// decide equality, so fingerprint collisions can never become repeated-block findings.
private struct AnalysisRepeatScanner
{
    representatives: Array'AnalysisRepeatRepresentative
    buckets:         [512] u16
    block:           Array'u8
    blockOffset:     u64
    blockCount:      u64
}

// Selects the checksums a streamed analysis computes.
struct AnalysisAlgorithms
{
    crc32:   bool = true
    crc64:   bool
    md5:     bool = true
    sha1:    bool = true
    sha256:  bool = true
    sha512:  bool
    blake2s: bool
    blake2b: bool
}

// One inferred readable run and the exact bytes that produced it.
struct AnalysisString
{
    offset: u64     // First byte of the run in the file.
    length: u64     // Bytes the run covers, two per character in UTF-16.
    kind:   AnalysisStringKind
    text:   String     // Readable preview, ending in `...` when the run is longer.
}

// Bounded findings for one explicit file range.
struct AnalysisResult
{
    range:            AnalysisRange
    scanned:          u64           // Bytes read before completion, cancellation, or failure.
    histogram:        [256] u64     // Occurrences of each byte value.
    zeroCount:        u64
    printableCount:   u64      // Bytes the text column shows as themselves.
    entropy:          f64      // Shannon entropy of the scanned bytes, in bits per byte.
    entropyBlockSize: u64      // Target byte width of each block; the last block may be shorter.
    entropyBlocks:    Array'AnalysisEntropyBlock
    repeatedBlocks:   Array'AnalysisRepeatedBlock // At most `AnalysisRepeatedPairLimit` exact pairs.
    repeatScanTruncated: bool   // More than the first `AnalysisRepeatRepresentativeLimit` unique blocks were seen.
    repeatHintsTruncated: bool  // More than `AnalysisRepeatedPairLimit` matching pairs were seen.
    strings:          Array'AnalysisString     // Inferred runs in file order, at most `AnalysisStringLimit`.
    stringsTruncated: bool     // Whether more runs were found than `strings` keeps.
    cancelled:        bool
    failureReason:    String                 // Empty unless the file could not be read.
    hasDigests:       bool                   // Whether every byte of the range was read, so the digests below cover it.
    algorithms:       AnalysisAlgorithms    // Algorithms selected for this complete result.
    crc32:            u32                    // CRC-32 of the range, as ZIP and PNG compute it.
    crc64:            u64                    // CRC-64/ECMA-182 of the range.
    sha256:           Hash.Sha256.Digest     // SHA-256 of the range.
    md5:              Hash.Md5.Digest        // MD5 of the range, which download pages still print.
    sha1:             Hash.Sha1.Digest       // SHA-1 of the range.
    sha512:           Hash.Sha512.Digest     // SHA-512 of the range.
    blake2s:          [32] u8               // BLAKE2s-256 of the range.
    blake2b:          [64] u8               // BLAKE2b-512 of the range.
}

private impl AnalysisRepeatScanner
{
    // Starts a block when needed and passes each complete 64 KiB block to the exact detector.
    mtd scan(value: u8, offset: u64, result: *AnalysisResult)
    {
        if not .blockCount do
            .blockOffset = offset
        .block[.blockCount] = value
        .blockCount += 1
        if .blockCount == AnalysisRepeatedBlockSize do
            .finishBlock(result)
    }

    mtd finishBlock(result: *AnalysisResult)
    {
        if result.repeatHintsTruncated
        {
            .resetBlock()
            return
        }

        let source = .block.toSlice()
        let fingerprint = Hash.hashBytes32(source)
        let bucket = fingerprint % AnalysisRepeatBucketCount
        var candidate = .buckets[bucket]
        while candidate
        {
            let representative = &.representatives[candidate - 1]
            if representative.fingerprint == fingerprint
            {
                var equal = true
                for index in AnalysisRepeatedBlockSize where representative.bytes[index] != .block[index]
                {
                    equal = false
                    break
                }

                if equal
                {
                    if result.repeatedBlocks.count < AnalysisRepeatedPairLimit
                    {
                        result.repeatedBlocks.add({representative.offset, .blockOffset, AnalysisRepeatedBlockSize})
                    }
                    else
                    {
                        result.repeatHintsTruncated = true
                    }
                    .resetBlock()
                    return
                }
            }
            candidate = representative.next
        }

        if .representatives.count < AnalysisRepeatRepresentativeLimit
        {
            var representative: AnalysisRepeatRepresentative
            representative.fingerprint = fingerprint
            representative.offset      = .blockOffset
            representative.next        = .buckets[bucket]
            representative.bytes.resize(AnalysisRepeatedBlockSize)
            for index in AnalysisRepeatedBlockSize do
                representative.bytes[index] = .block[index]
            .representatives.add(#move representative)
            .buckets[bucket] = cast(u16, .representatives.count)
        }
        else
        {
            result.repeatScanTruncated = true
        }
        .resetBlock()
    }

    mtd resetBlock()
    {
        .blockCount = 0
    }
}

impl AnalysisResult
{
    // Returns the CRC-32 of the range in hexadecimal, as checksum tools print it.
    mtd const crc32Text()->String => Format.toString("%{X08}", .crc32)

    // Returns the CRC-64/ECMA-182 of the range in hexadecimal.
    mtd const crc64Text()->String => Format.toString("%{X016}", .crc64)

    // Returns the MD5 of the range in lowercase hexadecimal, as checksum tools print it.
    mtd const md5Text()->String
    {
        const Digits = "0123456789abcdef"
        var result: String
        for byte in .md5
        {
            result.append(cast(rune, Digits[byte >> 4]))
            result.append(cast(rune, Digits[byte & 0xF]))
        }

        return result
    }

    // Returns the SHA-1 of the range in lowercase hexadecimal, as checksum tools print it.
    mtd const sha1Text()->String => wordsText(.sha1)

    // Returns the selected digests, one per line, each after its algorithm.
    mtd const digestsText()->String
    {
        var result: String
        if .algorithms.crc32 do result += Format.toString("CRC-32 %\n", .crc32Text())
        if .algorithms.crc64 do result += Format.toString("CRC-64/ECMA-182 %{X016}\n", .crc64)
        if .algorithms.md5 do result += Format.toString("MD5 %\n", .md5Text())
        if .algorithms.sha1 do result += Format.toString("SHA-1 %\n", .sha1Text())
        if .algorithms.sha256 do result += Format.toString("SHA-256 %\n", .sha256Text())
        if .algorithms.sha512 do result += Format.toString("SHA-512 %\n", wordsText(.sha512))
        if .algorithms.blake2s do result += Format.toString("BLAKE2s-256 %\n", bytesText(.blake2s))
        if .algorithms.blake2b do result += Format.toString("BLAKE2b-512 %\n", bytesText(.blake2b))
        return result
    }

    // Returns a copied checksum together with the exact half-open range it covers.
    mtd const digestCopyText(algorithm: string, digest: string)->String
    {
        let end = .range.offset + .range.length
        return Format.toString("% [0x%, 0x%) %", algorithm, Format.toString("%{X016}", .range.offset), Format.toString("%{X016}", end), digest)
    }

    // Returns the SHA-256 of the range in lowercase hexadecimal, as checksum tools print it.
    mtd const sha256Text()->String => wordsText(.sha256)

    mtd const sha512Text()->String => wordsText(.sha512)

    mtd const blake2sText()->String => bytesText(.blake2s)

    mtd const blake2bText()->String => bytesText(.blake2b)
}

// Writes the big-endian 32-bit words of a digest in lowercase hexadecimal.
private func wordsText(words: const [..] u32)->String
{
    const Digits = "0123456789abcdef"
    var result: String
    for word in words
    {
        for shift in 8 do
            result.append(cast(rune, Digits[(word >> (28 - shift * 4)) & 0xF]))
    }

    return result
}

private func wordsText(words: const [..] u64)->String
{
    const Digits = "0123456789abcdef"
    var result: String
    for word in words
    {
        for shift in 16 do
            result.append(cast(rune, Digits[(word >> (60 - shift * 4)) & 0xF]))
    }

    return result
}

private func bytesText(bytes: const [..] u8)->String
{
    const Digits = "0123456789abcdef"
    var result: String
    for byte in bytes
    {
        result.append(cast(rune, Digits[byte >> 4]))
        result.append(cast(rune, Digits[byte & 0xF]))
    }

    return result
}

// Readable run being accumulated in one encoding, flushed when a byte breaks it.
private struct StringScanner
{
    start:   u64
    length:  u64
    units:   u64
    preview: Array'u8
}

private impl StringScanner
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
        if .preview.count < AnalysisStringPreview do
            .preview.add(value)
    }

    // Ends the current string run and records it when it is long enough; past `AnalysisStringLimit`
    // strings only the truncation is noted. A preview shorter than its run ends in an ellipsis.
    mtd flush(kind: AnalysisStringKind, result: *AnalysisResult)
    {
        if .units >= AnalysisMinimumStringSize
        {
            if result.strings.count < AnalysisStringLimit
            {
                var entry = AnalysisString{offset: .start, length: .length, kind: kind}
                entry.text = cast(string, .preview.toSlice())
                if .units > .preview.count do
                    entry.text += "..."
                result.strings.add(#move entry)
            }
            else
            {
                result.stringsTruncated = true
            }
        }

        .reset()
    }
}

private impl AnalysisResult
{
    // Counts the byte at `offset` and extends or closes the ASCII run.
    mtd scanByte(ascii: *StringScanner, value: u8, offset: u64)
    {
        .histogram[value] += 1
        if value == 0 do
            .zeroCount += 1

        if isPrintable(value)
        {
            .printableCount += 1
            ascii.append(offset, 1, value)
        }
        else
        {
            ascii.flush(.Ascii, me)
        }
    }

    // Extends or closes the UTF-16 runs with the byte pair `first`, `second` at `offset`.
    mtd scanPair(little, big: *StringScanner, first, second: u8, offset: u64)
    {
        if isPrintable(first) and second == 0 do
            little.append(offset, 2, first)
        else do
            little.flush(.Utf16Little, me)

        if first == 0 and isPrintable(second) do
            big.append(offset, 2, second)
        else do
            big.flush(.Utf16Big, me)
    }

    // Closes every open run, orders the strings by offset, and derives the entropy.
    mtd finishScan(ascii: *StringScanner, little, big: *[2] StringScanner)
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
            let share = cast(f64, count) / cast(f64, .scanned)
            .entropy -= share * Math.log2(share)
        }
    }

    // Records the current partial block and clears its bounded byte histogram.
    mtd finishEntropyBlock(histogram: *[256] u64, blockScanned: *u64)
    {
        if not blockScanned[] do
            return

        var block: AnalysisEntropyBlock
        block.range = AnalysisRange{.range.offset + .scanned - blockScanned[], blockScanned[]}
        for count in histogram[] where count
        {
            let share = cast(f64, count) / cast(f64, blockScanned[])
            block.entropy -= share * Math.log2(share)
        }
        .entropyBlocks.add(#move block)
        blockScanned[] = 0
        for index in 256 do histogram[][index] = 0
    }
}

// Returns the byte counts, entropy, and a bounded set of inferred ASCII and UTF-16 runs of `range` in `fileName`.
//
// The range is streamed in `AnalysisChunkSize` chunks. A request to stop the work running the scan
// ([[Swag.isCancelled]]) ends it early with a partial result. `processed` is an optional atomic
// owned by an asynchronous caller, which follows the bytes scanned so far. A failure is reported in
// `failureReason`, never as an error.
func analyzeRange(fileName: string, range: AnalysisRange, processed: *u64? = null, algorithms: AnalysisAlgorithms = {})->AnalysisResult
{
    var result: #returntype
    result.range = range
    result.algorithms = algorithms
    if not range.length do
        return result
    if Swag.isCancelled()
    {
        result.cancelled = true
        return result
    }

    var stream = catch File.openReadLive(fileName)
    {
        result.failureReason = Viewer.failureText(Swag.err)
        return result
    }

    catch stream.seek(.Begin, range.offset)
    {
        result.failureReason = Viewer.failureText(Swag.err)
        return result
    }

    var ascii:       StringScanner
    var little:      [2] StringScanner
    var big:         [2] StringScanner
    var previous:    u8
    var hasPrevious: bool
    var blockHistogram: [256] u64
    var blockScanned:   u64
    var repeatScanner:  AnalysisRepeatScanner
    repeatScanner.block.resize(AnalysisRepeatedBlockSize)
    var bytes:       Array'u8
    var crc:         Hash.Crc32
    var sha:         Hash.Sha256
    var md5:         Hash.Md5
    var sha1:        Hash.Sha1
    var crc64:       Hash.Crc64
    var sha512:      Hash.Sha512
    var blake2s: Hash.Blake2s
    var blake2b: Hash.Blake2b
    if algorithms.blake2s
    {
        blake2s = catch Hash.Blake2s.create(32)
        {
            result.failureReason = Viewer.failureText(Swag.err)
            return result
        }
    }
    if algorithms.blake2b
    {
        blake2b = catch Hash.Blake2b.create(64)
        {
            result.failureReason = Viewer.failureText(Swag.err)
            return result
        }
    }
    if algorithms.crc64 do crc64.reset(.Ecma182)
    var remaining = range.length
    let estimatedBlockSize = range.length / AnalysisEntropyBlockLimit + (range.length % AnalysisEntropyBlockLimit ? 1 : 0)
    result.entropyBlockSize = Math.max(AnalysisEntropyBlockMinimum, estimatedBlockSize)
    while remaining
    {
        if Swag.isCancelled()
        {
            result.cancelled = true
            break
        }

        let wanted = Math.min(remaining, AnalysisChunkSize)
        bytes.resize(wanted)
        let count = catch stream.read(bytes.toSlice())
        {
            result.failureReason = Viewer.failureText(Swag.err)
            break
        }

        if not count
        {
            result.failureReason = texts().err_AnalysisShortRead
            break
        }

        bytes.resize(count)
        if algorithms.crc32 do crc.update(bytes.toSlice())
        if algorithms.crc64 do crc64.update(bytes.toSlice())
        if algorithms.sha256 do sha.update(bytes.toSlice())
        if algorithms.md5 do md5.update(bytes.toSlice())
        if algorithms.sha1 do sha1.update(bytes.toSlice())
        if algorithms.sha512 do sha512.update(bytes.toSlice())
        if algorithms.blake2s do blake2s.update(bytes.toSlice())
        if algorithms.blake2b do blake2b.update(bytes.toSlice())
        for value in bytes
        {
            let offset = range.offset + result.scanned
            result.scanByte(&ascii, value, offset)
            repeatScanner.scan(value, offset, &result)
            blockHistogram[value] += 1
            blockScanned += 1
            result.scanned += 1
            if blockScanned == result.entropyBlockSize do
                result.finishEntropyBlock(&blockHistogram, &blockScanned)
            if hasPrevious
            {
                let pairOffset = offset - 1
                let parity     = cast(u64, pairOffset & 1)
                result.scanPair(&little[parity], &big[parity], previous, value, pairOffset)
            }

            previous       = value
            hasPrevious    = true
        }

        if processed do
            Atomic.exchange(processed, result.scanned)
        remaining -= count
    }

    result.finishScan(&ascii, &little, &big)
    result.finishEntropyBlock(&blockHistogram, &blockScanned)
    if result.scanned == range.length and not result.cancelled and result.failureReason.isEmpty()
    {
        result.hasDigests = true
        if algorithms.crc32 do result.crc32 = crc.value()
        if algorithms.crc64 do result.crc64 = crc64.value()
        if algorithms.sha256 do result.sha256 = sha.finalize()
        if algorithms.md5 do result.md5 = md5.finalize()
        if algorithms.sha1 do result.sha1 = sha1.finalize()
        if algorithms.sha512 do result.sha512 = sha512.finalize()
        if algorithms.blake2s
        {
            catch blake2s.finalize(result.blake2s)
            {
                result.hasDigests = false
                result.failureReason = Viewer.failureText(Swag.err)
            }
        }
        if algorithms.blake2b
        {
            catch blake2b.finalize(result.blake2b)
            {
                result.hasDigests = false
                result.failureReason = Viewer.failureText(Swag.err)
            }
        }
    }

    return result
}

// Owns one cancellable analysis whose worker borrows this value until completion.
struct AnalysisOperation
{
    using operation: Viewer.BackgroundOperation
    fileName:        String
    range:           AnalysisRange
    algorithms:      AnalysisAlgorithms
    result:          AnalysisResult
    processed:       u64
}

impl AnalysisOperation
{
    // Starts analyzing `range` of `fileName` on a worker task; `owner` receives a
    // [[Gui.TaskEvent]] when it ends.
    //
    // The operation must not be started already: the previous result has to be collected with
    // [[AnalysisOperation.finish]] or discarded by [[AnalysisOperation.retire]] first.
    mtd start(fileName: string, range: AnalysisRange, owner: *Wnd? = null, algorithms: AnalysisAlgorithms = {})
    {
        Swag.assert(not .started)
        .fileName = fileName
        .range    = range
        .algorithms = algorithms
        .result   = {}
        Atomic.exchange(&.processed, 0)

        .submit(func|operation = me|()
        {
            operation.result = analyzeRange(operation.fileName, operation.range, &operation.processed, operation.algorithms)
        },
                owner)
    }

    // Asks a running analysis to stop; the partial result is still collected by [[AnalysisOperation.finish]].
    mtd cancel()
    {
        if .started do
            .task.cancel()
    }

    mtd progress()->u64 => Atomic.get(&.processed)

    // Returns the result of a finished analysis, and makes the operation ready to start again.
    mtd finish()->AnalysisResult
    {
        Swag.assert(.isDone())
        .wait()
        return #move .result
    }

    // Cancels active work, and reports whether the worker has let go of this operation so it can be destroyed.
    //
    // A retired analysis is no longer waited for.
    mtd retire()->bool
    {
        .cancel()
        if .started and not .isDone() do
            return false
        .wait()
        .abandon()
        return true
    }

    mtd opDrop()
    {
        .cancel()
        .wait()
    }
}
