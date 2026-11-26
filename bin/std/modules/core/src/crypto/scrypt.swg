#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

private alias SalsaVector = Math.Simd.U32x4
private alias SalsaBlock  = [4] SalsaVector
private const SalsaChunkSize = #sizeof(SalsaBlock)

private const SalsaShiftOne:   SalsaVector = [1, 2, 3, 0]
private const SalsaShiftTwo:   SalsaVector = [2, 3, 0, 1]
private const SalsaShiftThree: SalsaVector = [3, 0, 1, 2]

// The packed layout makes each vector lane one row, starting at its diagonal
// word. Integerify can still read the first word of the final chunk in place.
#[Swag.Inline]
private func scryptPack(block: *SalsaBlock)
{
    var original = state[]
    for round in 4
    {
        discard round
        state[][4]  ^= scryptRotateLeft(state[][0] + state[][12], 7)
        state[][8]  ^= scryptRotateLeft(state[][4] + state[][0], 9)
        state[][12] ^= scryptRotateLeft(state[][8] + state[][4], 13)
        state[][0]  ^= scryptRotateLeft(state[][12] + state[][8], 18)
        state[][9]  ^= scryptRotateLeft(state[][5] + state[][1], 7)
        state[][13] ^= scryptRotateLeft(state[][9] + state[][5], 9)
        state[][1]  ^= scryptRotateLeft(state[][13] + state[][9], 13)
        state[][5]  ^= scryptRotateLeft(state[][1] + state[][13], 18)
        state[][14] ^= scryptRotateLeft(state[][10] + state[][6], 7)
        state[][2]  ^= scryptRotateLeft(state[][14] + state[][10], 9)
        state[][6]  ^= scryptRotateLeft(state[][2] + state[][14], 13)
        state[][10] ^= scryptRotateLeft(state[][6] + state[][2], 18)
        state[][3]  ^= scryptRotateLeft(state[][15] + state[][11], 7)
        state[][7]  ^= scryptRotateLeft(state[][3] + state[][15], 9)
        state[][11] ^= scryptRotateLeft(state[][7] + state[][3], 13)
        state[][15] ^= scryptRotateLeft(state[][11] + state[][7], 18)

        state[][1]  ^= scryptRotateLeft(state[][0] + state[][3], 7)
        state[][2]  ^= scryptRotateLeft(state[][1] + state[][0], 9)
        state[][3]  ^= scryptRotateLeft(state[][2] + state[][1], 13)
        state[][0]  ^= scryptRotateLeft(state[][3] + state[][2], 18)
        state[][6]  ^= scryptRotateLeft(state[][5] + state[][4], 7)
        state[][7]  ^= scryptRotateLeft(state[][6] + state[][5], 9)
        state[][4]  ^= scryptRotateLeft(state[][7] + state[][6], 13)
        state[][5]  ^= scryptRotateLeft(state[][4] + state[][7], 18)
        state[][11] ^= scryptRotateLeft(state[][10] + state[][9], 7)
        state[][8]  ^= scryptRotateLeft(state[][11] + state[][10], 9)
        state[][9]  ^= scryptRotateLeft(state[][8] + state[][11], 13)
        state[][10] ^= scryptRotateLeft(state[][9] + state[][8], 18)
        state[][12] ^= scryptRotateLeft(state[][15] + state[][14], 7)
        state[][13] ^= scryptRotateLeft(state[][12] + state[][15], 9)
        state[][14] ^= scryptRotateLeft(state[][13] + state[][12], 13)
        state[][15] ^= scryptRotateLeft(state[][14] + state[][13], 18)
    }

    for index in 16
    {
        state[][index] += original[index]
    }

    Crypto.secureClear(original)
}

#[Swag.Inline]
private func scryptUnpack(block: *SalsaBlock)
{
    Math.Simd.transpose4x4(block)
    block[][1] = Swag.vecShuffle(block[][1], SalsaShiftThree)
    block[][2] = Swag.vecShuffle(block[][2], SalsaShiftTwo)
    block[][3] = Swag.vecShuffle(block[][3], SalsaShiftOne)
    let words = cast([*] u32, &block[][0])
    for word in SalsaChunkSize / #sizeof(u32) do
        words[word] = Math.nativeToLittleEndian(words[word])
}

#[Swag.Inline]
private func scryptSalsaRound(a, b, c, d: *SalsaVector)
{
    b[] ^= Swag.rol(a[] + d[], 7'u8)
    c[] ^= Swag.rol(b[] + a[], 9'u8)
    d[] ^= Swag.rol(c[] + b[], 13'u8)
    a[] ^= Swag.rol(d[] + c[], 18'u8)
}

private func scryptSalsa208(target: *SalsaBlock, previous, source: const *SalsaBlock)
{
    var a = previous[][0] ^ source[][0]
    var b = previous[][1] ^ source[][1]
    var c = previous[][2] ^ source[][2]
    var d = previous[][3] ^ source[][3]

    let startA = a
    let startB = b
    let startC = c
    let startD = d
    for 4
    {
        // Rotate the lanes into columns, then restore the row arrangement.
        var columnB = Swag.vecShuffle(d, SalsaShiftOne)
        var columnC = Swag.vecShuffle(c, SalsaShiftTwo)
        var columnD = Swag.vecShuffle(b, SalsaShiftThree)
        scryptSalsaRound(&a, &columnB, &columnC, &columnD)
        b = Swag.vecShuffle(columnD, SalsaShiftOne)
        c = Swag.vecShuffle(columnC, SalsaShiftTwo)
        d = Swag.vecShuffle(columnB, SalsaShiftThree)
        scryptSalsaRound(&a, &b, &c, &d)
    }

    target[][0] = startA + a
    target[][1] = startB + b
    target[][2] = startC + c
    target[][3] = startD + d
}

private func scryptBlockMix(source: const [*] SalsaBlock, target: [*] SalsaBlock, r: u32)
{
    let blockCount = cast(u64, r) * 2
    var previous   = &source[blockCount - 1]
    for chunk in blockCount
    {
        // BlockMix groups the even chunks before the odd chunks.
        let result = &target[chunk / 2 + (chunk % 2) * r]
        scryptSalsa208(result, previous, &source[chunk])

        // The output block becomes the input state for the next chunk.
        previous = result
    }

    var chunk = 0_u64
    while chunk < blockCount
    {
        let blockOffset = chunk * 64
        for word in 16
        {
            let offset = blockOffset + (word * 4)
            state[word] ^= cast(u32, block[offset]) |
                           (cast(u32, block[offset + 1]) << 8) |
                           (cast(u32, block[offset + 2]) << 16) |
                           (cast(u32, block[offset + 3]) << 24)
        }

        scryptSalsa208(&state)
        for word in 16
        {
            let offset = blockOffset + (word * 4)
            work[offset]     = cast(u8, state[word])
            work[offset + 1] = cast(u8, state[word] >> 8)
            work[offset + 2] = cast(u8, state[word] >> 16)
            work[offset + 3] = cast(u8, state[word] >> 24)
        }

        chunk += 1
    }

    let halfSize   = cast(u64, r) * 64
    var chunkIndex = 0_u32
    while chunkIndex < r
    {
        let evenOffset = cast(u64, chunkIndex) * 128
        let oddOffset  = evenOffset + 64
        Swag.memcpy(block.buffer + cast(u64, chunkIndex) * 64, work.buffer + evenOffset, 64)
        Swag.memcpy(block.buffer + halfSize + (cast(u64, chunkIndex) * 64), work.buffer + oddOffset, 64)
        chunkIndex += 1
    }

    Crypto.secureClear(state)
}

private func scryptRomix(block: [..] u8, costN: u32, blockR: u32, blockSize: u64)
{
    let vectorSize  = blockSize * costN
    let scratchSize = vectorSize + blockSize
    // Keep each Salsa chunk within its own cache line.
    let storage     = cast([*] u8, Memory.alloc(scratchSize, alignment: 64))
    defer
    {
        Crypto.secureClear(Swag.makeSlice(storage, scratchSize))
        Memory.free(storage, scratchSize)
    }

    let integerOffset = blockSize - 64
    let mask = cast(u64, costN - 1)
    index = 0
    while index < costN
    {
        var integer = 0_u64
        for byte in 8
        {
            integer |= cast(u64, block[integerOffset + byte]) << (byte * 8)
        }

        let selected     = integer & mask
        let vectorOffset = selected * blockSize
        var byte         = 0_u64
        while byte < blockSize
        {
            block[byte] ^= vector[vectorOffset + byte]
            byte        += 1
        }

    var current = blocks
    var next    = cast([*] SalsaBlock, storage + vectorSize)
    for index in costN
    {
        Swag.memcpy(storage + (cast(u64, index) * blockSize), current, blockSize)
        scryptBlockMix(current, next, blockR)
        let completed = next
        next    = current
        current = completed
    }

    const VectorSize = #sizeof(SalsaVector)
    let mask = costN - 1
    for costN
    {
        // N fits in 32 bits, so Integerify needs only the low word.
        let integer  = current[chunks - 1][0][0]
        let selected = cast(const [*] SalsaVector, storage + (cast(u64, integer & mask) * blockSize))
        let active   = cast([*] SalsaVector, current)
        for group in blockSize / VectorSize do
            active[group] ^= selected[group]

        scryptBlockMix(current, next, blockR)
        let completed = next
        next    = current
        current = completed
    }

    // The two N-step loops leave the final block in the caller's buffer.
    for chunk in chunks do
        scryptUnpack(&blocks[chunk])
}

// Derives a key with scrypt (RFC 7914) and an explicit upper bound on temporary memory.
//
// `costN` must be a power of two greater than one; `blockR` and `parallelP` must be positive.
// `maxMemoryBytes` bounds the ROMix vectors and working buffers before allocation. The output
// may be empty. Fails with [[Core.Errors.BadParameterError]] for invalid cost parameters or when
// the requested working set exceeds the memory bound.
func scrypt(password, salt: const [..] u8, costN, blockR, parallelP: u32, maxMemoryBytes: u64, destination: [..] u8) fail
{
    if costN < 2 or (costN & (costN - 1)) != 0 or not blockR or not parallelP
    {
        fail Errors.BadParameterError{"scrypt needs a power-of-two cost above one and positive r and p"}
    }

    if cast(u64, blockR) * parallelP >= (1_u64 << 30)
    {
        fail Errors.BadParameterError{"scrypt r times p exceeds the parameter limit"}
    }

    const SalsaBlockSize = 128_u64
    let blockSize = cast(u64, blockR) * SalsaBlockSize
    let laneCount = cast(u64, parallelP)
    if blockSize > Swag.U64.Max / laneCount
    {
        fail Errors.BadParameterError{"scrypt working set size overflows"}
    }

    let initialSize = blockSize * laneCount
    if cast(u64, costN) + 3 > Swag.U64.Max / initialSize
    {
        fail Errors.BadParameterError{"scrypt working set size overflows"}
    }

    let requiredMemory = initialSize * (cast(u64, costN) + 3)
    if requiredMemory > maxMemoryBytes
    {
        fail Errors.BadParameterError{"scrypt working set exceeds the memory limit"}
    }

    if not destination.count
    {
        return
    }

    var blocks: Array!{u8}
    blocks.resize(initialSize)
    defer Crypto.secureClear(blocks.toSlice())
    try pbkdf2HmacSha256(password, salt, 1, blocks.toSlice())

    // ROMix lanes are independent; each worker owns its block and its N-block vector.
    if parallelP > 1
    {
        catch parallel for |&blocks, costN, blockR, blockSize| lane in parallelP
        {
            let offset = cast(u64, lane) * blockSize
            scryptRomix(blocks.toSlice()[offset until offset + blockSize], costN, blockR, blockSize)
        }
        {
            fail Swag.err
        }
    }
    else
    {
        scryptRomix(blocks.toSlice(), costN, blockR, blockSize)
    }

    try pbkdf2HmacSha256(password, blocks.toSlice(), 1, destination)
}
