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

private const Blake3MessagePermutation: [16] u8 = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
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

#[Swag.Inline]
private func blake3Mix(state: *[16] u32, a, b, c, d, x, y: u32)
{
    state[][a] += state[][b] + x
    state[][d] = Swag.ror(state[][d] ^ state[][a], 16'u8)
    state[][c] += state[][d]
    state[][b] = Swag.ror(state[][b] ^ state[][c], 12'u8)
    state[][a] += state[][b] + y
    state[][d] = Swag.ror(state[][d] ^ state[][a], 8'u8)
    state[][c] += state[][d]
    state[][b] = Swag.ror(state[][b] ^ state[][c], 7'u8)
}

#[Swag.Inline]
private func blake3Compress(inputCv: [8] u32, block: [16] u32, counter: u64, blockSize, flags: u32)->[16] u32
{
    var state: [16] u32
    for index in 8
    {
        state[index]     = inputCv[index]
        state[index + 8] = Blake3Iv[index]
    }

    state[12] = cast(u32, counter)
    state[13] = cast(u32, (counter >> 32))
    state[14] = blockSize
    state[15] = flags

    var message = block
    for round in 7
    {
        blake3Mix(&state, 0, 4, 8, 12, message[0], message[1])
        blake3Mix(&state, 1, 5, 9, 13, message[2], message[3])
        blake3Mix(&state, 2, 6, 10, 14, message[4], message[5])
        blake3Mix(&state, 3, 7, 11, 15, message[6], message[7])
        blake3Mix(&state, 0, 5, 10, 15, message[8], message[9])
        blake3Mix(&state, 1, 6, 11, 12, message[10], message[11])
        blake3Mix(&state, 2, 7, 8, 13, message[12], message[13])
        blake3Mix(&state, 3, 4, 9, 14, message[14], message[15])

        if round < 6
        {
            var permuted: [16] u32
            for index in 16 do
                permuted[index] = message[Blake3MessagePermutation[index]]
            message = permuted
        }
    }

    for index in 8
    {
        state[index]     ^= state[index + 8]
        state[index + 8] ^= inputCv[index]
    }

    return state
}

private func blake3BlockWords(block: const [*] u8)->[16] u32
{
    var words: #returntype
    for index in 16
    {
        let offset = index * 4
        words[index] = cast(u32, block[offset]) |
                       (cast(u32, block[offset + 1]) << 8) |
                       (cast(u32, block[offset + 2]) << 16) |
                       (cast(u32, block[offset + 3]) << 24)
    }

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

private func blake3ChunkCv(data: const [*] u8, length, counter: u64, key: [8] u32, flags: u32)->[8] u32
{
    var cv         = key
    let blockCount = length ? ((length - 1) / Blake3BlockSize) + 1 : 1
    for blockIndex in blockCount
    {
        let offset    = blockIndex * Blake3BlockSize
        let blockSize = length > offset ? Math.min(length - offset, Blake3BlockSize) : 0
        var block: [Blake3BlockSize] u8
        if blockSize do
            Swag.memcpy(&block[0], data + offset, blockSize)
        var blockFlags = flags
        if not blockIndex do
            blockFlags |= Blake3ChunkStart
        if blockIndex + 1 == blockCount do
            blockFlags |= Blake3ChunkEnd
        let words      = blake3BlockWords(&block[0])
        let compressed = blake3Compress(cv, words, counter, cast(u32, blockSize), blockFlags)
        if blockIndex + 1 == blockCount
        {
            var result: [8] u32
            for index in 8 do
                result[index] = compressed[index]
            return result
        }

        for index in 8 do
            cv[index] = compressed[index]
    }

    unreachable
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
        let words = blake3BlockWords(key.buffer)
        var keyWords: [8] u32
        for index in 8 do
            keyWords[index] = words[index]
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

        .writeRootOutput(output, destination)
        .clear()
    }

    // Clears the chaining state and any buffered input.
    mtd clear()
    {
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
        let words = blake3BlockWords(key.buffer)
        var keyWords: [8] u32
        for index in 8 do
            keyWords[index] = words[index]
        try Blake3.computeWithKeyAndFlags(data, keyWords, Blake3KeyedHash, destination)
    }

    // Derives key material from a context string and input material as specified by BLAKE3.
    func deriveKey(context, inputKeyMaterial: const [..] u8, destination: [..] u8) fail
    {
        var contextHasher = Blake3.createWithKeyAndFlags(Blake3Iv, Blake3DeriveKeyContext)
        contextHasher.update(context)
        var contextOutput: [Blake3KeySize] u8
        try contextHasher.finalize(contextOutput)
        let keyWordsWithTail = blake3BlockWords(&contextOutput[0])
        var contextKey: [8] u32
        for index in 8 do
            contextKey[index] = keyWordsWithTail[index]
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
        let chunkCount = data.count ? ((data.count - 1) / Blake3ChunkSize) + 1 : 1
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
            let cv = blake3ChunkCv(input + chunkIndex * Blake3ChunkSize, Blake3ChunkSize, chunkIndex, key, flags)
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
        let words      = blake3BlockWords(&.block[0])
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
        result.block     = blake3BlockWords(&.block[0])
        result.counter   = .chunkCounter
        result.blockSize = cast(u32, .blockSize)
        result.flags     = flags
        return result
    }

    private mtd writeRootOutput(output: Blake3Output, destination: [..] u8)
    {
        var written       = 0'u64
        var outputCounter = 0'u64
        while written < destination.count
        {
            let words = blake3Compress(output.inputCv, output.block, outputCounter, output.blockSize, output.flags | Blake3Root)
            let count = Math.min(destination.count - written, Blake3BlockSize)
            for index in count
            {
                let word  = words[index / 4]
                let shift = cast(u32, (index % 4) * 8)
                destination[written + index] = cast(u8, (word >> shift) & 0xFF)
            }

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
