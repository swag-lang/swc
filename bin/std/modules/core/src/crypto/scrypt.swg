#global public
#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

private func scryptRotateLeft(value: u32, count: u32)->u32 => (value << count) | (value >> (32 - count))

private func scryptSalsa208(state: *[16] u32)
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

    for index in 16 do
        state[][index] += original[index]
    Crypto.secureClear(original)
}

private func scryptBlockMix(block: [..] u8, work: [..] u8, r: u32)
{
    var state: [16] u32
    let blockCount = cast(u64, r) * 2
    let lastOffset = (blockCount - 1) * 64
    for word in 16
    {
        let offset = lastOffset + (word * 4)
        state[word] = cast(u32, block[offset]) |
                      (cast(u32, block[offset + 1]) << 8) |
                      (cast(u32, block[offset + 2]) << 16) |
                      (cast(u32, block[offset + 3]) << 24)
    }

    var chunk = 0'u64
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
    var chunkIndex = 0'u32
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
    let vectorSize = blockSize * costN
    var vector: Array'u8
    vector.resize(vectorSize)
    var work: Array'u8
    work.resize(blockSize)

    var index = 0'u32
    while index < costN
    {
        Swag.memcpy(vector.toSlice().buffer + (cast(u64, index) * blockSize), block.buffer, blockSize)
        scryptBlockMix(block, work.toSlice(), blockR)
        index += 1
    }

    let integerOffset = blockSize - 64
    let mask = cast(u64, costN - 1)
    index = 0
    while index < costN
    {
        var integer = 0'u64
        for byte in 8 do
            integer |= cast(u64, block[integerOffset + byte]) << (byte * 8)
        let selected     = integer & mask
        let vectorOffset = selected * blockSize
        var byte         = 0'u64
        while byte < blockSize
        {
            block[byte] ^= vector[vectorOffset + byte]
            byte        += 1
        }

        scryptBlockMix(block, work.toSlice(), blockR)
        index += 1
    }

    Crypto.secureClear(vector.toSlice())
    Crypto.secureClear(work.toSlice())
}

// Derives a key with scrypt (RFC 7914) and an explicit upper bound on temporary memory.
//
// `costN` must be a power of two greater than one; `blockR` and `parallelP` must be positive.
// `maxMemoryBytes` bounds the ROMix vectors and working buffers before allocation. The output
// may be empty. Fails with [[Core.Errors.BadParameterError]] for invalid cost parameters or when
// the requested working set exceeds the memory bound.
func scrypt(password, salt: const [..] u8, costN, blockR, parallelP: u32, maxMemoryBytes: u64, destination: [..] u8) fail
{
    if costN < 2 or (costN & (costN - 1)) != 0 or not blockR or not parallelP do
        fail Errors.BadParameterError{"scrypt needs a power-of-two cost above one and positive r and p"}
    if cast(u64, blockR) * parallelP >= (1'u64 << 30) do
        fail Errors.BadParameterError{"scrypt r times p exceeds the parameter limit"}

    const SalsaBlockSize = 128'u64
    let blockSize = cast(u64, blockR) * SalsaBlockSize
    let laneCount = cast(u64, parallelP)
    if blockSize > Swag.U64.Max / laneCount do
        fail Errors.BadParameterError{"scrypt working set size overflows"}
    let initialSize = blockSize * laneCount
    if cast(u64, costN) + 3 > Swag.U64.Max / initialSize do
        fail Errors.BadParameterError{"scrypt working set size overflows"}
    let requiredMemory = initialSize * (cast(u64, costN) + 3)
    if requiredMemory > maxMemoryBytes do
        fail Errors.BadParameterError{"scrypt working set exceeds the memory limit"}
    if not destination.count do
        return

    var blocks: Array'u8
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
