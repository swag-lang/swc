#global private

// Advent of Code 2024 Day 9: compact a fragmented disk map by moving file
// blocks into free gaps, then compute a position-weighted checksum.
// Exercises: using on struct fields, namespace, #assert/#typeof, anonymous
// struct returns, default parameter values, break-to-label, C-style for.

const MaxBlocks = 131072'u32
const FreeId    = 0xFFFF'u16

const SampleInput  = "2333133121414131402"
const SmallInput   = "12345"
const TrivialInput = "9"

namespace DiskLayout
{
    struct Span
    {
        fileId: u16
        length: u16
    }

    struct DiskMap
    {
        using base: DiskMapData
    }

    struct DiskMapData
    {
        blocks:     #null [*] u16
        blockCount: u32
        fileCount:  u16
    }

    func initDiskMap(capacity: u32 = MaxBlocks)->DiskMap
    {
        var result: DiskMap
        result.blocks = cast(#null [*] u16) testAlloc(cast(u64) capacity * cast(u64) #sizeof(u16))
        Swag.assert(result.blocks != null)
        result.blockCount = 0
        result.fileCount  = 0
        return result
    }

    func freeDiskMap(dm: DiskMap)
    {
        if dm.blocks do
            testFree(dm.blocks)
    }

    func copyDiskMap(src: DiskMap, capacity: u32 = MaxBlocks)->DiskMap
    {
        var result = initDiskMap(capacity)
        result.blockCount = src.blockCount
        result.fileCount  = src.fileCount
        let dstBlocks = result.blocks!
        let srcBlocks = src.blocks!
        for src.blockCount
        {
            dstBlocks[cast(u32) Swag.index] = srcBlocks[cast(u32) Swag.index]
        }
        return result
    }

    func parseDiskMap(text: string)->DiskMap
    {
        let bytes  = cast(const [..] u8) text
        var result = initDiskMap()
        let blocks = result.blocks!
        var currentFileId: u16

        for bytes.count
        {
            let ch = bytes[Swag.index]
            if ch < '0' or ch > '9' do
                continue

            let runLength = cast(u32) (ch - '0')
            let isFile    = (Swag.index & 1) == 0

            #assert(#typeof(isFile) == bool)
            #assert(#typeof(runLength) == u32)

            let blockId = isFile ? currentFileId : FreeId
            for runLength
            {
                Swag.assert(result.blockCount < MaxBlocks)
                blocks[result.blockCount] = blockId
                result.blockCount         += 1
            }

            if isFile
            {
                currentFileId += 1
            }
        }

        result.fileCount = currentFileId
        return result
    }

    func blockAt(dm: DiskMap, pos: u32)->u16
    {
        Swag.assert(pos < dm.blockCount)
        let blocks = dm.blocks!
        return blocks[pos]
    }
}

// ---------------------------------------------------------------------------
// Part 1: block-level compaction (move one block at a time from end to
// leftmost free slot)
// ---------------------------------------------------------------------------

namespace Compaction
{
    using DiskLayout

    func compactBlocks(dm: *DiskMap)
    {
        if dm.blockCount < 2 do
            return

        var left: u32
        var right  = dm.blockCount - 1
        let blocks = dm.blocks!

        #scope(Outer)
        for
        {
            while left < right and blocks[left] != FreeId do
                left += 1
            while right > left and blocks[right] == FreeId do
                right -= 1
            if left >= right do
                break to Outer

            blocks[left]  = blocks[right]
            blocks[right] = FreeId
            left          += 1
            right         -= 1
        }
    }

    func compactWholeFiles(dm: *DiskMap)
    {
        if dm.fileCount == 0 do
            return

        var fileId = dm.fileCount - 1
        for
        {
            var fileStart: u32
            var fileLen:   u32
            findFileSpan(dm, fileId, &fileStart, &fileLen)

            if fileLen > 0
            {
                var gapStart: u32
                var gapLen:   u32
                if findGap(dm, fileLen, fileStart, &gapStart, &gapLen)
                {
                    moveFileToGap(dm, fileStart, fileLen, gapStart)
                }
            }

            if fileId == 0 do
                break
            fileId -= 1
        }
    }

    func findFileSpan(dm: DiskMap, fileId: u16, outStart: *u32, outLen: *u32)
    {
        outStart[] = 0
        outLen[]   = 0
        let blocks = dm.blocks!
        for var i = cast(s64) dm.blockCount - 1; i >= 0; i -= 1
        {
            if blocks[cast(u32) i] == fileId
            {
                outStart[] = cast(u32) i
                outLen[]   += 1
            }
            elif outLen[] > 0 do
                break
        }
    }

    func findGap(dm: DiskMap, minLen: u32, beforePos: u32, outStart: *u32, outLen: *u32)->bool
    {
        var pos: u32
        let blocks = dm.blocks!
        while pos < beforePos
        {
            if blocks[pos] != FreeId
            {
                pos += 1
                continue
            }

            var gapLen: u32
            let gapStart = pos
            while pos < beforePos and blocks[pos] == FreeId
            {
                gapLen += 1
                pos    += 1
            }

            if gapLen >= minLen
            {
                outStart[] = gapStart
                outLen[]   = gapLen
                return true
            }
        }

        return false
    }

    func moveFileToGap(dm: *DiskMap, fileStart, fileLen, gapStart: u32)
    {
        let blocks = dm.blocks!
        for fileLen
        {
            let offset = cast(u32) Swag.index
            blocks[gapStart + offset]  = blocks[fileStart + offset]
            blocks[fileStart + offset] = FreeId
        }
    }
}

// ---------------------------------------------------------------------------
// Checksum and report
// ---------------------------------------------------------------------------

namespace Checksum
{
    using DiskLayout

    func compute(dm: DiskMap)->u64
    {
        var total: u64
        let blocks = dm.blocks!
        for dm.blockCount
        {
            let pos = cast(u32) Swag.index
            let blk = blocks[pos]
            if blk != FreeId do
                total += cast(u64) pos * cast(u64) blk
        }
        return total
    }
}

struct DiskReport
{
    blockCount:        u32
    fileCount:         u16
    checksumBlocks:    u64
    checksumWholeFile: u64
}

func analyzeDisk(text: string)->DiskReport
{
    using DiskLayout
    using Compaction
    using Checksum

    var original = parseDiskMap(text)
    defer freeDiskMap(original)

    var result: DiskReport
    result.blockCount = original.blockCount
    result.fileCount  = original.fileCount

    var blockCopy = copyDiskMap(&original)
    defer freeDiskMap(blockCopy)
    compactBlocks(&blockCopy)
    result.checksumBlocks = compute(&blockCopy)

    var fileCopy = copyDiskMap(&original)
    defer freeDiskMap(fileCopy)
    compactWholeFiles(&fileCopy)
    result.checksumWholeFile = compute(&fileCopy)

    return result
}

func getSpanInfo(text: string)->{spanCount: u32, firstFree: u32}
{
    using DiskLayout
    let dm = parseDiskMap(text)
    defer freeDiskMap(dm)

    var spanCount: u32
    var firstFree: u32
    var prevId    = cast(u32) FreeId + 1
    var foundFree = false
    let blocks    = dm.blocks!
    for dm.blockCount
    {
        let pos = cast(u32) Swag.index
        let blk = blocks[pos]
        if cast(u32) blk != prevId
        {
            spanCount += 1
            prevId    = cast(u32) blk
        }
        if !foundFree and blk == FreeId
        {
            firstFree = pos
            foundFree = true
        }
    }

    return {spanCount, firstFree}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#test
{
    let sample = analyzeDisk(SampleInput)

    Swag.assert(sample.blockCount == 42'u32)
    Swag.assert(sample.fileCount == 10'u16)
    Swag.assert(sample.checksumBlocks == 1928'u64)
    Swag.assert(sample.checksumWholeFile == 2858'u64)
}

#test
{
    let small = analyzeDisk(SmallInput)

    Swag.assert(small.blockCount == 15'u32)
    Swag.assert(small.fileCount == 3'u16)
    Swag.assert(small.checksumBlocks == 60'u64)

    let info = getSpanInfo(SmallInput)
    Swag.assert(info.spanCount == 5'u32)
    Swag.assert(info.firstFree == 1'u32)
}

#test
{
    let trivial = analyzeDisk(TrivialInput)

    Swag.assert(trivial.blockCount == 9'u32)
    Swag.assert(trivial.fileCount == 1'u16)
    Swag.assert(trivial.checksumBlocks == 0'u64)
    Swag.assert(trivial.checksumWholeFile == 0'u64)
}
