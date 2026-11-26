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
    let words = cast([*] u32, &block[][0])
    for word in SalsaChunkSize / #sizeof(u32) do
        words[word] = Math.littleEndianToNative(words[word])
    block[][1] = Swag.vecShuffle(block[][1], SalsaShiftOne)
    block[][2] = Swag.vecShuffle(block[][2], SalsaShiftTwo)
    block[][3] = Swag.vecShuffle(block[][3], SalsaShiftThree)
    Math.Simd.transpose4x4(block)
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

private func scryptSalsa208(state: *SalsaBlock)
{
    var a = state[][0]
    var b = state[][1]
    var c = state[][2]
    var d = state[][3]
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

    state[][0] += a
    state[][1] += b
    state[][2] += c
    state[][3] += d
}

private func scryptBlockMix(source: const [*] SalsaBlock, target: [*] SalsaBlock, r: u32)
{
    let blockCount = cast(u64, r) * 2
    var state      = source[blockCount - 1]
    for chunk in blockCount
    {
        state[0] ^= source[chunk][0]
        state[1] ^= source[chunk][1]
        state[2] ^= source[chunk][2]
        state[3] ^= source[chunk][3]
        scryptSalsa208(&state)

        // BlockMix groups the even chunks before the odd chunks.
        target[chunk / 2 + (chunk % 2) * r] = state
    }

    Crypto.secureClear(state)
}

private func scryptRomix(block: [..] u8, costN: u32, blockR: u32, blockSize: u64)
{
    let vectorSize  = blockSize * costN
    let scratchSize = vectorSize + blockSize
    let storage     = cast([*] u8, Memory.alloc(scratchSize))
    defer
    {
        Crypto.secureClear(Swag.makeSlice(storage, scratchSize))
        Memory.free(storage, scratchSize)
    }

    let chunks = blockSize / SalsaChunkSize
    let blocks = cast([*] SalsaBlock, block.buffer)
    for chunk in chunks do
        scryptPack(&blocks[chunk])

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
