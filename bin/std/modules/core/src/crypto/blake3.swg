#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// BLAKE3's block size in bytes.
public const Blake3BlockSize = 64

// BLAKE3's chunk size in bytes.
public const Blake3ChunkSize = 1024

// BLAKE3 key size in bytes.
public const Blake3KeySize = 32

private const Blake3Iv: [8] u32 = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]

private const Blake3MessageSchedule: [7][16] u8 = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8],
    [3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1],
    [10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6],
    [12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4],
    [9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7],
    [11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13]]

private const Blake3ChunkStart        = 1_u32
private const Blake3ChunkEnd          = 2_u32
private const Blake3Parent            = 4_u32
private const Blake3Root              = 8_u32
private const Blake3KeyedHash         = 16_u32
private const Blake3DeriveKeyContext  = 32_u32
private const Blake3DeriveKeyMaterial = 64_u32

private struct Blake3Output
{
    inputCv:   [8] u32
    block:     [16] u32
    counter:   u64
    blockSize: u32
    flags:     u32
}

private alias Blake3Vector = Math.Simd.U32x4

private func(Words: u64, LittleEndianOutput: bool) blake3CompressTo(inputCv, block: const [*] u32, counter: u64, blockSize, flags: u32, destination: [*] u32)
{
    const Left   = cast(Blake3Vector, [1_u32, 2, 3, 0])
    const Across = cast(Blake3Vector, [2_u32, 3, 0, 1])
    const Right  = cast(Blake3Vector, [3_u32, 0, 1, 2])
    const Rot16  = cast(Math.Simd.U8x16, [2_u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
    const Rot8   = cast(Math.Simd.U8x16, [1_u8, 2, 3, 0, 5, 6, 7, 4, 9, 10, 11, 8, 13, 14, 15, 12])

    // Keep one state row in each SIMD vector.
    let cvLow  = Math.Simd.load(inputCv)
    let cvHigh = Math.Simd.load(inputCv + 4)
    var a      = cvLow
    var b      = cvHigh
    var c      = Math.Simd.load(&Blake3Iv[0])
    var d      = cast(Blake3Vector, [cast(u32, counter), cast(u32, (counter >> 32)), blockSize, flags])

    #[Swag.Mixin]
    func mix(x, y: Blake3Vector)
    {
        a += b + x
        d = cast #bit(Blake3Vector, Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, (d ^ a)), Rot16))
        c += d
        b = Math.ror(b ^ c, 12)
        a += b + y
        d = cast #bit(Blake3Vector, Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, (d ^ a)), Rot8))
        c += d
        b = Math.ror(b ^ c, 7)
    }

    #[Swag.Mixin]
    func mixRound(columnX, columnY, diagonalX, diagonalY: Blake3Vector)
    {
        mix(columnX, columnY)
        a = Math.Simd.permute(a, Right)
        c = Math.Simd.permute(c, Left)
        d = Math.Simd.permute(d, Across)
        mix(diagonalX, diagonalY)
        a = Math.Simd.permute(a, Left)
        c = Math.Simd.permute(c, Right)
        d = Math.Simd.permute(d, Across)
    }

    // Start the diagonal message vectors with the last word pair so row b stays in place.
    let block0    = Math.Simd.load(block)
    let block1    = Math.Simd.load(block + 4)
    let block2    = Math.Simd.load(block + 8)
    let block3    = Math.Simd.load(block + 12)
    var columnX   = Math.Simd.deinterleaveEven(block0, block1)
    var columnY   = Math.Simd.deinterleaveOdd(block0, block1)
    var diagonalX = Math.Simd.permute(Math.Simd.deinterleaveEven(block2, block3), Right)
    var diagonalY = Math.Simd.permute(Math.Simd.deinterleaveOdd(block2, block3), Right)

    mixRound(columnX, columnY, diagonalX, diagonalY)
    for 6
    {
        // Apply the BLAKE3 message permutation in each mix's lane order.
        let nextColumnX = Math.Simd.permute(Math.Simd.permute2(columnX, columnY, cast(Blake3Vector, [2_u32, 1, 5, 7])), Left)
        let nextColumnY = Math.Simd.permute2(columnX,
                                             Math.Simd.permute2(diagonalX, diagonalY, cast(Blake3Vector, [2_u32, 2, 7, 7])),
                                             cast(Blake3Vector, [3_u32, 4, 0, 6]))
        let nextDiagonalX = Math.Simd.permute2(diagonalY,
                                               Math.Simd.permute2(columnY, diagonalX, cast(Blake3Vector, [0_u32, 0, 7, 7])),
                                               cast(Blake3Vector, [0_u32, 4, 6, 1]))
        let nextDiagonalY = Math.Simd.permute2(diagonalX,
                                               Math.Simd.permute2(diagonalY, columnY, cast(Blake3Vector, [2_u32, 2, 6, 6])),
                                               cast(Blake3Vector, [1_u32, 4, 6, 0]))

        columnX   = nextColumnX
        columnY   = nextColumnY
        diagonalX = nextDiagonalX
        diagonalY = nextDiagonalY
        mixRound(columnX, columnY, diagonalX, diagonalY)
    }

    blake3StoreWords!{LittleEndianOutput}(destination, a ^ c)
    blake3StoreWords!{LittleEndianOutput}(destination + 4, b ^ d)
    #static if Words == 16
    {
        blake3StoreWords!{LittleEndianOutput}(destination + 8, c ^ cvLow)
        blake3StoreWords!{LittleEndianOutput}(destination + 12, d ^ cvHigh)
    }
}

#[Swag.Inline]
private func(LittleEndian: bool) blake3StoreWords(destination: [*] u32, value: Blake3Vector)
{
    #static if LittleEndian
    {
        Math.Simd.store(destination, Math.nativeToLittleEndian(value))
    }
    else
    {
        Math.Simd.store(destination, value)
    }
}

private func(Count: u64) blake3ReadWords(block: const [*] u8)->[Count] u32
{
    let source = cast(const [*] u32, block)
    var words: #returntype
    for index in Count
    {
        words[index] = Math.littleEndianToNative(source[index])
    }

    return words
}

// The compressor reads both halves of the current CV before writing the next CV in place.
#[Swag.Inline]
private func blake3CompressBlock(cv: [*] u32, bytes: const [*] u8, counter: u64, flags: u32)
{
    #static if BIG_ENDIAN
    {
        let words = blake3ReadWords!{16}(bytes)
        blake3CompressTo!{8, false}(cv, &words[0], counter, Blake3BlockSize, flags, cv)
    }
    else
    {
        blake3CompressTo!{8, false}(cv, cast(const [*] u32, bytes), counter, Blake3BlockSize, flags, cv)
    }
}

private func blake3OutputCv(output: const *Blake3Output)->[8] u32
{
    var cv: #returntype
    blake3CompressTo!{8, false}(&output.inputCv[0], &output.block[0], output.counter, output.blockSize, output.flags, &cv[0])
    return cv
}

private func blake3ParentOutput(key: [8] u32, left, right: [8] u32, flags: u32)->Blake3Output
{
    var result: #returntype
    result.inputCv = key
    for index in 8
    {
        result.block[index]     = left[index]
        result.block[index + 8] = right[index]
    }

    result.blockSize = Blake3BlockSize
    result.flags     = flags | Blake3Parent
    return result
}

private func blake3ChunkOutput(data: const [..] u8, counter: u64, key: [8] u32, flags: u32)->Blake3Output
{
    var output: #returntype
    output.inputCv   = key
    output.counter   = counter
    output.flags     = flags | Blake3ChunkStart
    output.blockSize = Blake3BlockSize

    var offset = 0_u64
    while data.count - offset > Blake3BlockSize
    {
        blake3CompressBlock(&output.inputCv[0], data.buffer + offset, counter, output.flags)
        output.flags = flags
        offset       += Blake3BlockSize
    }

    let remaining = data.count - offset
    output.blockSize = cast(u32, remaining)
    output.flags     |= Blake3ChunkEnd
    if remaining == Blake3BlockSize
    {
        output.block = blake3ReadWords!{16}(data.buffer + offset)
    }
    else
    {
        var tail: [Blake3BlockSize] u8
        if remaining
        {
            Swag.memcpy(&tail[0], data.buffer + offset, remaining)
        }

        output.block = blake3ReadWords!{16}(&tail[0])
        Crypto.secureClear(tail)
    }

    return output
}

private const Blake3ChunksPerBatch = 4
private const Blake3WordsPerCv     = Blake3KeySize / #sizeof(u32)

// Large updates can amortize worker scheduling across several complete batches.
private const Blake3ParallelBytes  = 64 * 1024
private const Blake3BlocksPerChunk = Blake3ChunkSize / Blake3BlockSize

#[Swag.Mixin]
private func blake3MixChunk(a, b, c, d: *Blake3Vector, x, y: Blake3Vector)
{
    a[] += b[] + x
    d[] = Math.ror(d[] ^ a[], 16)
    c[] += d[]
    b[] = Math.ror(b[] ^ c[], 12)
    a[] += b[] + y
    d[] = Math.ror(d[] ^ a[], 8)
    c[] += d[]
    b[] = Math.ror(b[] ^ c[], 7)
}

#[Swag.Mixin]
private func(Round: u64) blake3MixChunkRound(a0, a1, a2, a3, b0, b1, b2, b3,
                                            c0, c1, c2, c3, d0, d1, d2, d3: *Blake3Vector,
                                            message: const *[16] Blake3Vector)
{
    scope
    {
        const Schedule = Blake3MessageSchedule[Round]
        blake3MixChunk(a0, b0, c0, d0, message[][Schedule[0]], message[][Schedule[1]])
        blake3MixChunk(a1, b1, c1, d1, message[][Schedule[2]], message[][Schedule[3]])
        blake3MixChunk(a2, b2, c2, d2, message[][Schedule[4]], message[][Schedule[5]])
        blake3MixChunk(a3, b3, c3, d3, message[][Schedule[6]], message[][Schedule[7]])
        blake3MixChunk(a0, b1, c2, d3, message[][Schedule[8]], message[][Schedule[9]])
        blake3MixChunk(a1, b2, c3, d0, message[][Schedule[10]], message[][Schedule[11]])
        blake3MixChunk(a2, b3, c0, d1, message[][Schedule[12]], message[][Schedule[13]])
        blake3MixChunk(a3, b0, c1, d2, message[][Schedule[14]], message[][Schedule[15]])
    }
}

// When the final block stays buffered, return the last lane's chaining value before it.
private func(Parent: bool, Chunks: u64) blake3BatchCvs(input: const [*] u8, firstChunk: u64, key: [8] u32, flags: u32, keepLastInput = false)->[Chunks][8] u32
{
    // A leaf lane covers sixteen message blocks, while a parent combines two native chaining values.
    const Blocks        = Parent ? 1 : Blake3BlocksPerChunk
    const CounterStride = Parent ? 0_u64 : 1
    const InputStride   = Parent ? Blake3BlockSize : Blake3ChunkSize
    var cv: [8] Blake3Vector
    for index in 8
    {
        cv[index] = Math.Simd.splat(key[index])
    }

    let low = cast(Blake3Vector, [cast(u32, firstChunk), cast(u32, (firstChunk + 1 * CounterStride)),
                                  cast(u32, (firstChunk + 2 * CounterStride)), cast(u32, (firstChunk + 3 * CounterStride))])
    let high = cast(Blake3Vector, [cast(u32, (firstChunk >> 32)), cast(u32, ((firstChunk + 1 * CounterStride) >> 32)),
                                   cast(u32, ((firstChunk + 2 * CounterStride) >> 32)), cast(u32, ((firstChunk + 3 * CounterStride) >> 32))])
    let blockSize = Math.Simd.splat(cast(u32, Blake3BlockSize))
    for blockIndex in Blocks
    {
        let base = input + blockIndex * Blake3BlockSize
        var message: [16] Blake3Vector
        for group in 4
        {
            let bytes = cast(const [*] u32, base + group * #sizeof(Blake3Vector))
            const WordStride = InputStride / #sizeof(u32)
            const LastChunk  = Chunks - 1
            const ThirdChunk = Chunks == 2 ? LastChunk : 2
            // Unused lanes load the last complete chunk and their outputs are discarded.
            var rows: [4] Blake3Vector = [
                Math.Simd.load(bytes), Math.Simd.load(bytes + WordStride),
                Math.Simd.load(bytes + WordStride * ThirdChunk), Math.Simd.load(bytes + WordStride * LastChunk)]
            Math.Simd.transpose4x4(&rows)
            for index in 4
            {
                #static if Parent
                {
                    message[group * 4 + index] = rows[index]
                }
                else
                {
                    message[group * 4 + index] = Math.littleEndianToNative(rows[index])
                }
            }
        }

        var blockFlags = flags
        #static if Parent
        {
            blockFlags |= Blake3Parent
        }
        else
        {
            if blockIndex == 0
            {
                blockFlags |= Blake3ChunkStart
            }
            if blockIndex == Blake3BlocksPerChunk - 1
            {
                blockFlags |= Blake3ChunkEnd
            }
        }
        // Keep the round state in separate vector locals so mixes can reuse registers.
        var a0 = cv[0]
        var a1 = cv[1]
        var a2 = cv[2]
        var a3 = cv[3]
        var b0 = cv[4]
        var b1 = cv[5]
        var b2 = cv[6]
        var b3 = cv[7]
        var c0 = Math.Simd.splat(Blake3Iv[0])
        var c1 = Math.Simd.splat(Blake3Iv[1])
        var c2 = Math.Simd.splat(Blake3Iv[2])
        var c3 = Math.Simd.splat(Blake3Iv[3])
        var d0 = low
        var d1 = high
        var d2 = blockSize
        var d3 = Math.Simd.splat(blockFlags)

        blake3MixChunkRound!{0}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)
        blake3MixChunkRound!{1}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)
        blake3MixChunkRound!{2}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)
        blake3MixChunkRound!{3}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)
        blake3MixChunkRound!{4}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)
        blake3MixChunkRound!{5}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)
        blake3MixChunkRound!{6}(&a0, &a1, &a2, &a3, &b0, &b1, &b2, &b3,
                                &c0, &c1, &c2, &c3, &d0, &d1, &d2, &d3, &message)

        var next: [8] Blake3Vector = [a0 ^ c0, a1 ^ c1, a2 ^ c2, a3 ^ c3,
                                       b0 ^ d0, b1 ^ d1, b2 ^ d2, b3 ^ d3]
        if not Parent and keepLastInput and blockIndex == Blake3BlocksPerChunk - 1
        {
            const RetainLast = cast(Blake3Vector, [0_u32, Chunks == 2 ? Swag.U32.Max : 0,
                                                   Chunks == 3 ? Swag.U32.Max : 0,
                                                   Chunks == 4 ? Swag.U32.Max : 0])
            for index in 8
            {
                next[index] = Math.Simd.select(RetainLast, cv[index], next[index])
            }
        }

        cv = next
    }

    var result: #returntype
    for offset in [0_u64, 4]
    {
        var words: [4] Blake3Vector = [cv[offset], cv[offset + 1], cv[offset + 2], cv[offset + 3]]
        Math.Simd.transpose4x4(&words)
        for chunk in Chunks
        {
            Math.Simd.store(&result[chunk][offset], words[chunk])
        }
    }

    return result
}

private const Blake3SubtreeChunks = 2 * Blake3ChunksPerBatch

private func blake3EightChunkSubtreeCv(children: const [*] u32, key: [8] u32, flags: u32)->[8] u32
{
    let parents     = blake3BatchCvs!{true, Blake3ChunksPerBatch}(cast(const [*] u8, children), 0, key, flags)
    let leftParent  = blake3ParentOutput(key, parents[0], parents[1], flags)
    let rightParent = blake3ParentOutput(key, parents[2], parents[3], flags)
    let parent      = blake3ParentOutput(key, blake3OutputCv(&leftParent), blake3OutputCv(&rightParent), flags)
    return blake3OutputCv(&parent)
}

private func blake3HashCompleteSubtree(input: const [*] u8, firstChunk: u64, key: [8] u32, flags: u32)->[8] u32
{
    const BatchSize = Blake3ChunksPerBatch * Blake3ChunkSize
    var leaves: [Blake3SubtreeChunks][8] u32
    for batch in 2
    {
        let cvs = blake3BatchCvs!{false, Blake3ChunksPerBatch}(input + batch * BatchSize,
                                                               firstChunk + batch * Blake3ChunksPerBatch, key, flags)
        Swag.memcpy(&leaves[batch * Blake3ChunksPerBatch][0], &cvs[0][0], #sizeof(cvs))
    }
    return blake3EightChunkSubtreeCv(&leaves[0][0], key, flags)
}

private func blake3HashBatches(input: const [*] u8, output: [*] u32, batches, firstChunk: u64, key: [8] u32, flags: u32)
{
    parallel for |input, output, firstChunk, key, flags| batch in batches
    {
        let chunk = batch * Blake3ChunksPerBatch
        let cvs   = blake3BatchCvs!{false, Blake3ChunksPerBatch}(input + chunk * Blake3ChunkSize, firstChunk + chunk, key, flags)
        Swag.memcpy(output + chunk * Blake3WordsPerCv, &cvs[0][0], #sizeof(cvs))
    }
}

private func blake3HashSubtrees(input: const [*] u8, output: [*] u32, subtrees, firstChunk: u64, key: [8] u32, flags: u32)
{
    parallel for |input, output, firstChunk, key, flags| subtree in subtrees
    {
        let chunk = subtree * Blake3SubtreeChunks
        let cv = blake3HashCompleteSubtree(input + chunk * Blake3ChunkSize, firstChunk + chunk, key, flags)
        Swag.memcpy(output + subtree * Blake3WordsPerCv, &cv[0], #sizeof(cv))
    }
}

// Stores an incremental BLAKE3 sequence with unkeyed, keyed, or context-derived key state.
#[Swag.NoCopy, Swag.Opaque]
public struct Blake3
{
    key:              [8] u32
    chunkCv:          [8] u32
    chunkCounter:     u64
    block:            [Blake3BlockSize] u8
    blockSize:        u64
    blocksCompressed: u32
    flags:            u32
    cvStack:          [54][8] u32
    stackSize:        u64
    initialized:      bool
}

public impl Blake3
{
    // Creates an unkeyed BLAKE3 sequence.
    func create()->Blake3
    {
        var result: #returntype
        result.reset()
        return result
    }

    // Creates a keyed BLAKE3 sequence from exactly 32 key bytes.
    func createKeyed(key: const [..] u8)->Blake3 fail
    {
        var result: #returntype
        try result.resetKeyed(key)
        return result
    }

    // Replaces any previous state and starts an unkeyed sequence.
    mtd reset()
    {
        .resetWithKey(Blake3Iv, 0)
    }

    // Replaces any previous state and starts a keyed sequence from exactly 32 bytes.
    mtd resetKeyed(key: const [..] u8) fail
    {
        if key.count != Blake3KeySize
        {
            fail Errors.BadParameterError{"BLAKE3 keyed hashing needs exactly 32 key bytes"}
        }

        let keyWords = blake3ReadWords!{8}(key.buffer)
        .resetWithKey(keyWords, Blake3KeyedHash)
    }

    // Includes `data` in the running BLAKE3 sequence.
    mtd update(data: const [..] u8)
    {
        let useWorkers = data.count >= Blake3ParallelBytes and Swag.workerCount() > 1
        .updateChunks(data, useWorkers)
    }

    private mtd updateChunks(data: const [..] u8, useWorkers: bool)
    {
        Swag.assert(.initialized, "BLAKE3 needs an initialized sequence")
        let input  = data.buffer
        var offset = 0_u64
        while offset < data.count
        {
            if .blockSize == Blake3BlockSize
            {
                if .blocksCompressed == Blake3BlocksPerChunk - 1
                {
                    let output = .chunkOutput()
                    .pushSubtreeCv(blake3OutputCv(&output), .chunkCounter + 1)
                    .chunkCounter     += 1
                    .chunkCv          = .key
                    .blocksCompressed = 0
                    .blockSize        = 0
                    Crypto.secureClear(.block)
                }
                else
                {
                    .compressBlock(&.block[0])
                    .blockSize = 0
                    Crypto.secureClear(.block)
                }
            }

            // Preserve the final chunk's last block for root output.
            const BatchBytes = Blake3ChunksPerBatch * Blake3ChunkSize
            let remaining = data.count - offset
            if .blockSize == 0 and .blocksCompressed == 0 and remaining >= BatchBytes
            {
                if useWorkers and remaining >= Blake3ParallelBytes
                {
                    let batches = (remaining - 1) / BatchBytes
                    .pushParallelBatches(input + offset, batches)
                    offset += batches * BatchBytes
                    continue
                }

                if remaining > 2 * BatchBytes and .chunkCounter % Blake3SubtreeChunks == 0
                {
                    let cv = blake3HashCompleteSubtree(input + offset, .chunkCounter, .key, .flags)
                    .pushSubtreeCv(cv, .chunkCounter / Blake3SubtreeChunks + 1)
                    .chunkCounter += Blake3SubtreeChunks
                    offset        += 2 * BatchBytes
                    continue
                }

                .pushLeafBatch!{Blake3ChunksPerBatch}(input + offset, remaining)
                offset += BatchBytes
                continue
            }

            const PairBytes   = 2 * Blake3ChunkSize
            const TripleBytes = 3 * Blake3ChunkSize
            if .blockSize == 0 and .blocksCompressed == 0 and remaining >= PairBytes
            {
                if remaining >= TripleBytes
                {
                    .pushLeafBatch!{3}(input + offset, remaining)
                    offset += TripleBytes
                }
                else
                {
                    .pushLeafBatch!{2}(input + offset, remaining)
                    offset += PairBytes
                }
                continue
            }

            // A following byte proves this complete block cannot be the chunk's root block.
            if .blockSize == 0 and
               .blocksCompressed < Blake3BlocksPerChunk - 1 and
               data.count - offset > Blake3BlockSize
            {
                .compressBlock(input + offset)
                offset += Blake3BlockSize
                continue
            }

            let count = Math.min(data.count - offset, Blake3BlockSize - .blockSize)
            Swag.memcpy(&.block[.blockSize], input + offset, count)
            .blockSize += count
            offset     += count
        }
    }

    // Finalizes the sequence into an extendable output of any requested length, then clears state.
    mtd finalize(destination: [..] u8) fail
    {
        if not .initialized
        {
            fail Errors.BadParameterError{"BLAKE3 needs an initialized sequence"}
        }

        var output     = .chunkOutput()
        var stackIndex = .stackSize
        while stackIndex
        {
            stackIndex -= 1
            output     = blake3ParentOutput(.key, .cvStack[stackIndex], blake3OutputCv(&output), .flags)
        }

        writeRootOutput(&output, destination)
        .clear()
    }

    // Clears the chaining state and any buffered input.
    mtd clear()
    {
        if not .initialized
        {
            return
        }

        Crypto.secureClear(.key)
        Crypto.secureClear(.chunkCv)
        Crypto.secureClear(.block)
        Crypto.secureClear(.cvStack)
        .chunkCounter     = 0
        .blockSize        = 0
        .blocksCompressed = 0
        .flags            = 0
        .stackSize        = 0
        .initialized      = false
    }

    // Computes an unkeyed BLAKE3 output in one operation. The destination length selects the XOF length.
    func compute(data: const [..] u8, destination: [..] u8) fail
    {
        try Blake3.computeWithKeyAndFlags(data, Blake3Iv, 0, destination)
    }

    // Computes a keyed BLAKE3 output in one operation. `key` must contain exactly 32 bytes.
    func computeKeyed(key, data: const [..] u8, destination: [..] u8) fail
    {
        if key.count != Blake3KeySize
        {
            fail Errors.BadParameterError{"BLAKE3 keyed hashing needs exactly 32 key bytes"}
        }

        let keyWords = blake3ReadWords!{8}(key.buffer)
        try Blake3.computeWithKeyAndFlags(data, keyWords, Blake3KeyedHash, destination)
    }

    // Derives key material from a context string and input material as specified by BLAKE3.
    func deriveKey(context, inputKeyMaterial: const [..] u8, destination: [..] u8) fail
    {
        var contextHasher = Blake3.createWithKeyAndFlags(Blake3Iv, Blake3DeriveKeyContext)
        contextHasher.update(context)
        var contextOutput: [Blake3KeySize] u8
        try contextHasher.finalize(contextOutput)
        var contextKey = blake3ReadWords!{8}(&contextOutput[0])
        Crypto.secureClear(contextOutput)
        var materialHasher = Blake3.createWithKeyAndFlags(contextKey, Blake3DeriveKeyMaterial)
        materialHasher.update(inputKeyMaterial)
        try materialHasher.finalize(destination)
        Crypto.secureClear(contextKey)
    }

    private func createWithKeyAndFlags(key: [8] u32, flags: u32)->Blake3
    {
        var result: #returntype
        result.resetWithKey(key, flags)
        return result
    }

    private mtd resetWithKey(key: [8] u32, flags: u32)
    {
        .clear()
        .key         = key
        .chunkCv     = key
        .flags       = flags
        .initialized = true
    }

    private func computeWithKeyAndFlags(data: const [..] u8, key: [8] u32, flags: u32, destination: [..] u8) fail
    {
        if data.count <= Blake3ChunkSize
        {
            var output = blake3ChunkOutput(data, 0, key, flags)
            writeRootOutput(&output, destination)
            Crypto.secureClear(Swag.makeSlice(&output, 1))
            return
        }

        let chunkCount = (data.count - 1) / Blake3ChunkSize + 1
        let workers    = Swag.workerCount()
        if workers <= 1 or chunkCount <= 32 or chunkCount < cast(u64, workers) * 2
        {
            var hash = Blake3.createWithKeyAndFlags(key, flags)
            hash.updateChunks(data, false)
            try hash.finalize(destination)
            return
        }

        var hash = Blake3.createWithKeyAndFlags(key, flags)
        const BatchBytes = Blake3ChunksPerBatch * Blake3ChunkSize
        let batches = (chunkCount - 1) / Blake3ChunksPerBatch
        hash.pushParallelBatches(data.buffer, batches)
        hash.updateChunks(data[batches * BatchBytes to], false)
        try hash.finalize(destination)
    }

    #[Swag.Inline]
    private mtd(Chunks: u64) pushLeafBatch(input: const [*] u8, remaining: u64)
    {
        const BatchBytes   = Chunks * Blake3ChunkSize
        let retainLast     = remaining == BatchBytes
        let cvs            = blake3BatchCvs!{false, Chunks}(input, .chunkCounter, .key, .flags, retainLast)
        let completeChunks = retainLast ? Chunks - 1 : Chunks
        for chunk in completeChunks
        {
            .pushSubtreeCv(cvs[chunk], .chunkCounter + 1)
            .chunkCounter += 1
        }

        if retainLast
        {
            .chunkCv          = cvs[Chunks - 1]
            .blocksCompressed = Blake3BlocksPerChunk - 1
            .blockSize        = Blake3BlockSize
            Swag.memcpy(&.block[0], input + BatchBytes - Blake3BlockSize, Blake3BlockSize)
        }
    }

    private mtd pushParallelBatches(input: const [*] u8, batches: u64)
    {
        if batches >= 2 and .chunkCounter % Blake3SubtreeChunks == 0
        {
            let subtrees = batches / 2
            var chainingValues: Array!{u32}
            chainingValues.resize(subtrees * Blake3WordsPerCv)
            let output = unwrap chainingValues.buffer
            blake3HashSubtrees(input, output, subtrees, .chunkCounter, .key, .flags)
            for subtree in subtrees
            {
                var cv: [Blake3WordsPerCv] u32
                Swag.memcpy(&cv[0], output + subtree * Blake3WordsPerCv, #sizeof(cv))
                .pushSubtreeCv(cv, .chunkCounter / Blake3SubtreeChunks + 1)
                .chunkCounter += Blake3SubtreeChunks
            }
            if batches % 2 != 0
            {
                let cvs = blake3BatchCvs!{false, Blake3ChunksPerBatch}(input + subtrees * Blake3SubtreeChunks * Blake3ChunkSize,
                                                                       .chunkCounter, .key, .flags)
                for cv in cvs
                {
                    .pushSubtreeCv(cv, .chunkCounter + 1)
                    .chunkCounter += 1
                }
            }
            return
        }

        var chainingValues: Array!{u32}
        chainingValues.resize(batches * Blake3ChunksPerBatch * Blake3WordsPerCv)
        let output = unwrap chainingValues.buffer
        blake3HashBatches(input, output, batches, .chunkCounter, .key, .flags)
        for chunk in batches * Blake3ChunksPerBatch
        {
            var cv: [Blake3WordsPerCv] u32
            Swag.memcpy(&cv[0], output + chunk * Blake3WordsPerCv, #sizeof(cv))
            .pushSubtreeCv(cv, .chunkCounter + 1)
            .chunkCounter += 1
        }
    }

    private mtd pushSubtreeCv(cv: [8] u32, totalSubtrees: u64)
    {
        var totalChunks = totalSubtrees
        var merged      = cv
        while (totalChunks & 1) == 0
        {
            Swag.assert(.stackSize, "BLAKE3 chaining value stack underflow")
            .stackSize -= 1
            let parent = blake3ParentOutput(.key, .cvStack[.stackSize], merged, .flags)
            merged      = blake3OutputCv(&parent)
            totalChunks >>= 1
        }

        Swag.assert(.stackSize < 54, "BLAKE3 input exceeds the tree stack capacity")
        .cvStack[.stackSize] = merged
        .stackSize += 1
    }

    private mtd compressBlock(block: const [*] u8)
    {
        var blockFlags = .flags
        if not .blocksCompressed
        {
            blockFlags |= Blake3ChunkStart
        }

        blake3CompressBlock(&.chunkCv[0], block, .chunkCounter, blockFlags)

        .blocksCompressed += 1
    }

    private mtd chunkOutput()->Blake3Output
    {
        var flags = .flags | Blake3ChunkEnd
        if not .blocksCompressed
        {
            flags |= Blake3ChunkStart
        }

        var result: #returntype
        result.inputCv   = .chunkCv
        result.block     = blake3ReadWords!{16}(&.block[0])
        result.counter   = .chunkCounter
        result.blockSize = cast(u32, .blockSize)
        result.flags     = flags
        return result
    }

    private func writeRootOutput(output: const *Blake3Output, destination: [..] u8)
    {
        let flags = output.flags | Blake3Root
        if destination.count == #sizeof(output.inputCv)
        {
            blake3CompressTo!{8, true}(&output.inputCv[0], &output.block[0], 0, output.blockSize, flags, cast([*] u32, destination.buffer))
            return
        }

        var written       = 0_u64
        var outputCounter = 0_u64
        while destination.count - written >= Blake3BlockSize
        {
            let words = cast([*] u32, destination.buffer + written)
            blake3CompressTo!{16, true}(&output.inputCv[0], &output.block[0], outputCounter, output.blockSize, flags, words)
            written       += Blake3BlockSize
            outputCounter += 1
        }

        if written < destination.count
        {
            var words: [16] u32
            blake3CompressTo!{16, true}(&output.inputCv[0], &output.block[0], outputCounter, output.blockSize, flags, &words[0])
            Swag.memcpy(destination.buffer + written, &words[0], destination.count - written)
        }
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}
