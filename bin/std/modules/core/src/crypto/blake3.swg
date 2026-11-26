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

private const Blake3ChunkStart        = 1'u32
private const Blake3ChunkEnd          = 2'u32
private const Blake3Parent            = 4'u32
private const Blake3Root              = 8'u32
private const Blake3KeyedHash         = 16'u32
private const Blake3DeriveKeyContext  = 32'u32
private const Blake3DeriveKeyMaterial = 64'u32

private struct Blake3Output
{
    inputCv:   [8] u32
    block:     [16] u32
    counter:   u64
    blockSize: u32
    flags:     u32
}

private alias Blake3Vector = Math.Simd.U32x4

private func blake3Compress(inputCv: [8] u32, block: [16] u32, counter: u64, blockSize, flags: u32)->[16] u32
{
    const Left   = cast(Blake3Vector, [1'u32, 2, 3, 0])
    const Across = cast(Blake3Vector, [2'u32, 3, 0, 1])
    const Right  = cast(Blake3Vector, [3'u32, 0, 1, 2])
    const Rot16  = cast(Math.Simd.U8x16, [2'u8, 3, 0, 1, 6, 7, 4, 5, 10, 11, 8, 9, 14, 15, 12, 13])
    const Rot8   = cast(Math.Simd.U8x16, [1'u8, 2, 3, 0, 5, 6, 7, 4, 9, 10, 11, 8, 13, 14, 15, 12])

    // Keep one state row in each SIMD vector.
    let cvLow  = Math.Simd.load(&inputCv[0])
    let cvHigh = Math.Simd.load(&inputCv[4])
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
    let block0    = Math.Simd.load(&block[0])
    let block1    = Math.Simd.load(&block[4])
    let block2    = Math.Simd.load(&block[8])
    let block3    = Math.Simd.load(&block[12])
    var columnX   = Math.Simd.deinterleaveEven(block0, block1)
    var columnY   = Math.Simd.deinterleaveOdd(block0, block1)
    var diagonalX = Math.Simd.permute(Math.Simd.deinterleaveEven(block2, block3), Right)
    var diagonalY = Math.Simd.permute(Math.Simd.deinterleaveOdd(block2, block3), Right)

    mixRound(columnX, columnY, diagonalX, diagonalY)
    for 6
    {
        // Apply the BLAKE3 message permutation in each mix's lane order.
        let nextColumnX = Math.Simd.permute(Math.Simd.permute2(columnX, columnY, cast(Blake3Vector, [2'u32, 1, 5, 7])), Left)
        let nextColumnY = Math.Simd.permute2(columnX,
                                             Math.Simd.permute2(diagonalX, diagonalY, cast(Blake3Vector, [2'u32, 2, 7, 7])),
                                             cast(Blake3Vector, [3'u32, 4, 0, 6]))
        let nextDiagonalX = Math.Simd.permute2(diagonalY,
                                               Math.Simd.permute2(columnY, diagonalX, cast(Blake3Vector, [0'u32, 0, 7, 7])),
                                               cast(Blake3Vector, [0'u32, 4, 6, 1]))
        let nextDiagonalY = Math.Simd.permute2(diagonalX,
                                               Math.Simd.permute2(diagonalY, columnY, cast(Blake3Vector, [2'u32, 2, 6, 6])),
                                               cast(Blake3Vector, [1'u32, 4, 6, 0]))

        columnX   = nextColumnX
        columnY   = nextColumnY
        diagonalX = nextDiagonalX
        diagonalY = nextDiagonalY
        mixRound(columnX, columnY, diagonalX, diagonalY)
    }

    var state: #returntype
    Math.Simd.store(&state[0], a ^ c)
    Math.Simd.store(&state[4], b ^ d)
    Math.Simd.store(&state[8], c ^ cvLow)
    Math.Simd.store(&state[12], d ^ cvHigh)
    return state
}

#[Swag.Inline]
private func(Count: u64) blake3ReadWords(block: const [*] u8)->[Count] u32
{
    let source = cast(const [*] u32, block)
    var words: #returntype
    for index in Count do
        words[index] = Math.littleEndianToNative(source[index])
    return words
}

private func blake3OutputCv(output: Blake3Output)->[8] u32
{
    let words = blake3Compress(output.inputCv, output.block, output.counter, output.blockSize, output.flags)
    var cv: [8] u32
    for index in 8 do
        cv[index] = words[index]
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

    var offset = 0'u64
    while data.count - offset > Blake3BlockSize
    {
        output.block   = blake3ReadWords'16(data.buffer + offset)
        output.inputCv = blake3OutputCv(output)
        output.flags   = flags
        offset         += Blake3BlockSize
    }

    let remaining = data.count - offset
    output.blockSize = cast(u32, remaining)
    output.flags     |= Blake3ChunkEnd
    if remaining == Blake3BlockSize
    {
        output.block = blake3ReadWords'16(data.buffer + offset)
    }
    else
    {
        var tail: [Blake3BlockSize] u8
        if remaining do
            Swag.memcpy(&tail[0], data.buffer + offset, remaining)
        output.block = blake3ReadWords'16(&tail[0])
        Crypto.secureClear(tail)
    }

    return output
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
        if key.count != Blake3KeySize do
            fail Errors.BadParameterError{"BLAKE3 keyed hashing needs exactly 32 key bytes"}
        let keyWords = blake3ReadWords'8(key.buffer)
        .resetWithKey(keyWords, Blake3KeyedHash)
    }

    // Includes `data` in the running BLAKE3 sequence.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "BLAKE3 needs an initialized sequence")
        let input  = data.buffer
        var offset = 0'u64
        while offset < data.count
        {
            if .blockSize == Blake3BlockSize
            {
                if .blocksCompressed == 15
                {
                    let output = .chunkOutput()
                    .pushChunkCv(blake3OutputCv(output))
                    .chunkCounter     += 1
                    .chunkCv          = .key
                    .blocksCompressed = 0
                    .blockSize        = 0
                    Crypto.secureClear(.block)
                }
                else
                {
                    .compressBlock()
                }
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
        if not .initialized do
            fail Errors.BadParameterError{"BLAKE3 needs an initialized sequence"}

        var output     = .chunkOutput()
        var stackIndex = .stackSize
        while stackIndex
        {
            stackIndex -= 1
            output     = blake3ParentOutput(.key, .cvStack[stackIndex], blake3OutputCv(output), .flags)
        }

        writeRootOutput(output, destination)
        .clear()
    }

    // Clears the chaining state and any buffered input.
    mtd clear()
    {
        if not .initialized do
            return

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
        if key.count != Blake3KeySize do
            fail Errors.BadParameterError{"BLAKE3 keyed hashing needs exactly 32 key bytes"}
        let keyWords = blake3ReadWords'8(key.buffer)
        try Blake3.computeWithKeyAndFlags(data, keyWords, Blake3KeyedHash, destination)
    }

    // Derives key material from a context string and input material as specified by BLAKE3.
    func deriveKey(context, inputKeyMaterial: const [..] u8, destination: [..] u8) fail
    {
        var contextHasher = Blake3.createWithKeyAndFlags(Blake3Iv, Blake3DeriveKeyContext)
        contextHasher.update(context)
        var contextOutput: [Blake3KeySize] u8
        try contextHasher.finalize(contextOutput)
        var contextKey = blake3ReadWords'8(&contextOutput[0])
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
            writeRootOutput(output, destination)
            Crypto.secureClear(Swag.makeSlice(&output, 1))
            return
        }

        let chunkCount = (data.count - 1) / Blake3ChunkSize + 1
        if chunkCount < Math.max(4'u64, cast(u64, Swag.workerCount()) * 2)
        {
            var hash = Blake3.createWithKeyAndFlags(key, flags)
            hash.update(data)
            try hash.finalize(destination)
            return
        }

        var chainingValues: Array'u32
        chainingValues.resize((chunkCount - 1) * 8)
        let input  = data.buffer
        let output = unwrap chainingValues.buffer
        parallel for |input, output, key, flags| chunkIndex in chunkCount - 1
        {
            let chunk = Swag.makeSlice(input + chunkIndex * Blake3ChunkSize, Blake3ChunkSize)
            let cv    = blake3OutputCv(blake3ChunkOutput(chunk, chunkIndex, key, flags))
            for word in 8 do
                output[chunkIndex * 8 + word] = cv[word]
        }

        var hash = Blake3.createWithKeyAndFlags(key, flags)
        for chunkIndex in chunkCount - 1
        {
            var cv: [8] u32
            for word in 8 do
                cv[word] = chainingValues[chunkIndex * 8 + word]
            hash.chunkCounter = chunkIndex
            hash.pushChunkCv(cv)
        }

        let finalOffset = (chunkCount - 1) * Blake3ChunkSize
        hash.chunkCounter = chunkCount - 1
        hash.update(data[finalOffset to])
        try hash.finalize(destination)
    }

    private mtd pushChunkCv(cv: [8] u32)
    {
        var totalChunks = .chunkCounter + 1
        var merged      = cv
        while (totalChunks & 1) == 0
        {
            Swag.assert(.stackSize, "BLAKE3 chaining value stack underflow")
            .stackSize -= 1
            let parent = blake3ParentOutput(.key, .cvStack[.stackSize], merged, .flags)
            merged      = blake3OutputCv(parent)
            totalChunks >>= 1
        }

        Swag.assert(.stackSize < 54, "BLAKE3 input exceeds the tree stack capacity")
        .cvStack[.stackSize] = merged
        .stackSize += 1
    }

    private mtd compressBlock()
    {
        var blockFlags = .flags
        if not .blocksCompressed do
            blockFlags |= Blake3ChunkStart
        let words      = blake3ReadWords'16(&.block[0])
        let compressed = blake3Compress(.chunkCv, words, .chunkCounter, Blake3BlockSize, blockFlags)
        for index in 8 do
            .chunkCv[index] = compressed[index]
        .blocksCompressed += 1
        .blockSize        = 0
        Crypto.secureClear(.block)
    }

    private mtd chunkOutput()->Blake3Output
    {
        var flags = .flags | Blake3ChunkEnd
        if not .blocksCompressed do
            flags |= Blake3ChunkStart
        var result: #returntype
        result.inputCv   = .chunkCv
        result.block     = blake3ReadWords'16(&.block[0])
        result.counter   = .chunkCounter
        result.blockSize = cast(u32, .blockSize)
        result.flags     = flags
        return result
    }

    private func writeRootOutput(output: Blake3Output, destination: [..] u8)
    {
        var written       = 0'u64
        var outputCounter = 0'u64
        while written < destination.count
        {
            let words = blake3Compress(output.inputCv, output.block, outputCounter, output.blockSize, output.flags | Blake3Root)
            let count = Math.min(destination.count - written, Blake3BlockSize)
            #static if BIG_ENDIAN
            {
                var littleEndian: [16] u32
                for index in 16 do
                    littleEndian[index] = Math.nativeToLittleEndian(words[index])
                Swag.memcpy(destination.buffer + written, &littleEndian[0], count)
            }
            else do
                Swag.memcpy(destination.buffer + written, &words[0], count)

            written       += count
            outputCounter += 1
        }
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }
}
