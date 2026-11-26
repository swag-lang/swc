#global namespace Crypto
#global #[Swag.Safety(.Overflow, false)]

// Size in bytes of one Argon2 memory block.
public const Argon2BlockSize = 1024

// Smallest salt Argon2 accepts, in bytes. RFC 9106 recommends sixteen.
public const Argon2MinSaltSize = 8

// Smallest tag Argon2 produces, in bytes.
public const Argon2MinTagSize = 4

private const Argon2Words        = Argon2BlockSize / #sizeof(u64)
private const Argon2SyncPoints   = 4
private const Argon2AddressCount = Argon2Words
private const Argon2Version      = 0x13
private const Argon2TypeId       = 2

// Cost parameters for one Argon2id derivation.
//
// The defaults follow the RFC 9106 second recommended option. These three values
// and the tag length are the whole reproducibility contract: store them next to
// the tag they produced, because raising a cost later must not invalidate what
// was already derived.
public struct Argon2Parameters
{
    public
    {
        memoryKib:   u32 = 65536     // Memory cost in kibibytes, at least eight times `parallelism`.
        iterations:  u32 = 3         // Number of passes over memory, at least one.
        parallelism: u32 = 4         // Number of independent lanes, at least one.
    }
}

#[Swag.Inline]
private func truncate32(value: u64)->u64 => value & 0xFFFF_FFFF

#[Swag.Inline]
private func store32Le(data: [*] u8, value: u32)
{
    for i in 4 do
        data[i] = cast(u8, ((value >> cast(u32, (i * 8))) & 0xFF))
}

private alias Argon2Pair = Math.Simd.U64x2
private const Argon2Pairs = Argon2Words / 2

#[Swag.Inline]
private func blamka(a, b: Argon2Pair)->Argon2Pair
{
    const LowHalf: Argon2Pair = [0xFFFF_FFFF, 0xFFFF_FFFF]
    let product = (a & LowHalf) * (b & LowHalf)
    return (a + b) + (product + product)
}

#[Swag.Inline]
private func mixPairs(a, b, c, d: *Argon2Pair)
{
    const Rotate32: Math.Simd.U32x4 = [1, 0, 3, 2]
    const Rotate24: Math.Simd.U8x16 = [3, 4, 5, 6, 7, 0, 1, 2, 11, 12, 13, 14, 15, 8, 9, 10]
    const Rotate16: Math.Simd.U8x16 = [2, 3, 4, 5, 6, 7, 0, 1, 10, 11, 12, 13, 14, 15, 8, 9]

    a[] = blamka(a[], b[])
    d[] = cast #bit (Argon2Pair, Swag.vecShuffle(cast #bit (Math.Simd.U32x4, d[] ^ a[]), Rotate32))
    c[] = blamka(c[], d[])
    b[] = cast #bit (Argon2Pair, Swag.vecShuffle(cast #bit (Math.Simd.U8x16, b[] ^ c[]), Rotate24))
    a[] = blamka(a[], b[])
    d[] = cast #bit (Argon2Pair, Swag.vecShuffle(cast #bit (Math.Simd.U8x16, d[] ^ a[]), Rotate16))
    c[] = blamka(c[], d[])
    b[] = Swag.ror(b[] ^ c[], 63'u8)
}

// Each lane handles an independent G. Realign the pairs between the column
// and diagonal steps, then restore the original word order.
#[Swag.Inline]
private func(Stride: u64) permute(block: [*] Argon2Pair)
{
    var a0 = block[0]
    var a1 = block[Stride]
    var b0 = block[2 * Stride]
    var b1 = block[3 * Stride]
    var c0 = block[4 * Stride]
    var c1 = block[5 * Stride]
    var d0 = block[6 * Stride]
    var d1 = block[7 * Stride]

    mixPairs(&a0, &b0, &c0, &d0)
    mixPairs(&a1, &b1, &c1, &d1)

    var b0Diagonal = Swag.vecAlign(b0, b1, 8)
    var b1Diagonal = Swag.vecAlign(b1, b0, 8)
    var d0Diagonal = Swag.vecAlign(d1, d0, 8)
    var d1Diagonal = Swag.vecAlign(d0, d1, 8)
    mixPairs(&a0, &b0Diagonal, &c1, &d0Diagonal)
    mixPairs(&a1, &b1Diagonal, &c0, &d1Diagonal)

    block[0]          = a0
    block[Stride]     = a1
    block[2 * Stride] = Swag.vecAlign(b1Diagonal, b0Diagonal, 8)
    block[3 * Stride] = Swag.vecAlign(b0Diagonal, b1Diagonal, 8)
    block[4 * Stride] = c0
    block[5 * Stride] = c1
    block[6 * Stride] = Swag.vecAlign(d0Diagonal, d1Diagonal, 8)
    block[7 * Stride] = Swag.vecAlign(d1Diagonal, d0Diagonal, 8)
}

// Argon2's compression function. Writes `G(x, y)` to `destination`, or XORs it
// into `destination` when `accumulate` is set, which is what the second and
// later passes do.
private func compress(destination: [*] u64, x, y: const [*] u64, accumulate: bool)
{
    let left   = cast(const [*] Argon2Pair, x)
    let right  = cast(const [*] Argon2Pair, y)
    let target = cast([*] Argon2Pair, destination)
    var result: [Argon2Pairs] Argon2Pair

    for i in Argon2Pairs do
        result[i] = left[i] ^ right[i]

    for i in 8 do
        permute'1(&result[i * 8])
    for i in 8 do
        permute'8(&result[i])

    // Address generation can overwrite its right operand. Read each pair's
    // inputs before publishing the corresponding output.
    if accumulate
    {
        for i in Argon2Pairs do
            target[i] ^= result[i] ^ left[i] ^ right[i]
    }
    else
    {
        for i in Argon2Pairs do
            target[i] = result[i] ^ left[i] ^ right[i]
    }

    secureClear(result)
}

// RFC 9106 variable-length hash `H'`. BLAKE2b caps its digest at 64 bytes, so a
// longer request chains 64-byte digests and keeps 32 bytes of each.
private func variableHash(input: const [..] u8, destination: [..] u8) fail
{
    var prefix: [4] u8
    store32Le(&prefix[0], cast(u32, destination.count))

    if destination.count <= Hash.Blake2bMaxDigestSize
    {
        var hash = try Hash.Blake2b.create(destination.count)
        hash.update(prefix)
        hash.update(input)
        try hash.finalize(destination)
        return
    }

    var current: [Hash.Blake2bMaxDigestSize] u8
    defer secureClear(current)

    var hash = try Hash.Blake2b.create(Hash.Blake2bMaxDigestSize)
    hash.update(prefix)
    hash.update(input)
    try hash.finalize(current)

    // Each full round contributes its first 32 bytes. The tail is hashed at its
    // exact length rather than truncated, because BLAKE2b binds the digest
    // length into its state and the two do not agree.
    const strideSize = Hash.Blake2bMaxDigestSize / 2
    var written = 0'u64
    while destination.count - written > Hash.Blake2bMaxDigestSize
    {
        Swag.memcpy(destination.buffer + written, &current[0], strideSize)
        written += strideSize
        if destination.count - written > Hash.Blake2bMaxDigestSize do
            try Hash.Blake2b.compute(current, current)
    }

    let remaining = destination.count - written
    var tail: [Hash.Blake2bMaxDigestSize] u8
    defer secureClear(tail)
    try Hash.Blake2b.compute(current, tail[0 until remaining])
    Swag.memcpy(destination.buffer + written, &tail[0], remaining)
}

// Regenerates the block of pseudo-random addresses used by the data-independent passes.
//
// The address counter in `input` advances first, so each call yields the next block of addresses.
private func nextAddresses(addresses, input: [*] u64, zero: const [*] u64)
{
    input[6] += 1
    compress(addresses, zero, input, false)
    compress(addresses, zero, addresses, false)
}

// A segment owns its destination blocks and scratch. References into other lanes only
// reach completed slices, so joining each slice makes those reads safe.
private func fillSegment(blocks: [*] u64, lanes, passes, segmentLength, laneLength, blockCount, pass, slice, lane: u64)
{
    var zero:      [Argon2Words] u64
    var input:     [Argon2Words] u64
    var addresses: [Argon2Words] u64
    defer secureClear(input)
    defer secureClear(addresses)

    // Argon2id takes its addresses from a counter for the first half
    // of the first pass, and from the previous block afterwards.
    let independent = not pass and slice < Argon2SyncPoints / 2
    if independent
    {
        Swag.memset(&input[0], 0, Argon2BlockSize)
        input[0] = pass
        input[1] = lane
        input[2] = slice
        input[3] = blockCount
        input[4] = passes
        input[5] = Argon2TypeId
    }

    let firstSlice = not pass and not slice
    let sliceStart = slice * segmentLength
    let laneStart  = lane * laneLength
    let firstStep  = firstSlice ? 2 : 0
    if firstSlice do
        nextAddresses(&addresses[0], &input[0], &zero[0])

    // During the first pass only earlier slices are visible in other lanes.
    // Later passes have all three previous slices available.
    let priorBlocks = pass ? laneLength - segmentLength : sliceStart
    let windowStart = pass and slice != Argon2SyncPoints - 1 ? sliceStart + segmentLength : 0
    let laneMask    = lanes - 1
    let powerOfTwo  = (lanes & laneMask) == 0

    let firstIndex = sliceStart + firstStep
    var current    = blocks + ((laneStart + firstIndex) * Argon2Words)
    var previous   = firstIndex ? current - Argon2Words : blocks + ((laneStart + laneLength - 1) * Argon2Words)
    for step in firstStep until segmentLength
    {
        var random: u64
        if independent
        {
            let address = step % Argon2AddressCount
            if address == 0 do
                nextAddresses(&addresses[0], &input[0], &zero[0])
            random = addresses[address]
        }
        else
        {
            random = previous[0]
        }

        var referenceLane = lane
        if not firstSlice
        {
            let laneNumber = random >> 32
            referenceLane = powerOfTwo ? laneNumber & laneMask : laneNumber % lanes
        }

        // The RFC 9106 mapping squares the low word to bias references towards
        // recent blocks. The current lane may also use earlier blocks in this slice.
        let areaSize = referenceLane == lane ? priorBlocks + step - 1 : priorBlocks - (step ? 0 : 1)
        let low      = truncate32(random)
        let scaled   = (low * low) >> 32
        let relative = areaSize - 1 - ((areaSize * scaled) >> 32)
        var offset   = windowStart + relative
        if offset >= laneLength do
            offset -= laneLength

        let reference = blocks + ((referenceLane * laneLength + offset) * Argon2Words)
        compress(current, previous, reference, pass != 0)
        previous = current
        current  += Argon2Words
    }
}

// Derives a key from `password` and `salt` with Argon2id, RFC 9106, and fills `destination` with it.
//
// Argon2id spends the first half of its first pass on data-independent
// addressing and everything after it on data-dependent addressing, which is what
// gives it both side-channel resistance and resistance to time-memory tradeoffs.
// It is the variant to choose unless an existing format demands another one.
//
// `salt` holds at least 8 bytes and should hold 16. `destination` holds at least
// 4 bytes. `parameters.memoryKib` is at least eight times `parameters.parallelism`,
// and the derivation allocates that many kibibytes.
// Fails with [[Core.Errors.BadParameterError]] when a password, salt, associated-data, or
// destination length exceeds Argon2's 32-bit fields.
//
// The same password, salt, parameters, and destination length always produce the
// same bytes, on every platform. Independent lanes share the runtime worker pool when
// their segments are large enough; the call joins them before returning or clearing memory.
//
// ```swag
// var salt: [16] u8
// try Crypto.randomBytes(salt)
//
// var key: [32] u8
// try Crypto.argon2id("correct horse battery staple", salt, {memoryKib: 65536, iterations: 3, parallelism: 4}, key)
// ```
public func argon2id(password, salt: const [..] u8, parameters: Argon2Parameters, destination: [..] u8) fail
{
    try argon2id(password, salt, "", "", parameters, destination)
}

// Derives a key with Argon2id like the first overload, also binding `secret` and `associatedData` into it.
//
// `secret` is the RFC 9106 key input: a value the verifier holds but the
// password database does not, at most 64 bytes. `associatedData` binds a context
// such as a user identifier. Both are optional, and both must be reproduced
// exactly to reproduce the tag.
public func argon2id(password, salt, secret, associatedData: const [..] u8, parameters: Argon2Parameters, destination: [..] u8) fail
{
    if password.count > Swag.U32.Max or
       salt.count > Swag.U32.Max or
       associatedData.count > Swag.U32.Max or
       destination.count > Swag.U32.Max do
        fail Errors.BadParameterError{"Argon2 byte lengths exceed the 32-bit limit"}

    if destination.count < Argon2MinTagSize do
        fail Errors.BadParameterError{"Argon2 needs a tag of at least 4 bytes"}
    if salt.count < Argon2MinSaltSize do
        fail Errors.BadParameterError{"Argon2 needs a salt of at least 8 bytes"}
    if not parameters.parallelism or parameters.parallelism > 0xFF_FFFF do
        fail Errors.BadParameterError{"Argon2 needs 1 to 16777215 lanes"}
    if not parameters.iterations do
        fail Errors.BadParameterError{"Argon2 needs at least one pass"}
    if parameters.memoryKib < 8 * parameters.parallelism do
        fail Errors.BadParameterError{"Argon2 needs at least eight kibibytes of memory per lane"}
    if secret.count > Hash.Blake2bMaxKeySize do
        fail Errors.BadParameterError{"Argon2 accepts a secret of at most 64 bytes"}

    let lanes         = cast(u64, parameters.parallelism)
    let passes        = cast(u64, parameters.iterations)
    let segmentLength = cast(u64, parameters.memoryKib) / (Argon2SyncPoints * lanes)
    let laneLength    = segmentLength * Argon2SyncPoints
    let blockCount    = laneLength * lanes

    // The initial hash binds every parameter, so no two configurations can share
    // a derivation even with the same password and salt.
    var seed: [Hash.Blake2bMaxDigestSize] u8
    defer secureClear(seed)

    var initial = try Hash.Blake2b.create(Hash.Blake2bMaxDigestSize)
    var scalar: [4] u8
    store32Le(&scalar[0], parameters.parallelism)
    initial.update(scalar)
    store32Le(&scalar[0], cast(u32, destination.count))
    initial.update(scalar)
    store32Le(&scalar[0], parameters.memoryKib)
    initial.update(scalar)
    store32Le(&scalar[0], parameters.iterations)
    initial.update(scalar)
    store32Le(&scalar[0], Argon2Version)
    initial.update(scalar)
    store32Le(&scalar[0], Argon2TypeId)
    initial.update(scalar)
    store32Le(&scalar[0], cast(u32, password.count))
    initial.update(scalar)
    initial.update(password)
    store32Le(&scalar[0], cast(u32, salt.count))
    initial.update(scalar)
    initial.update(salt)
    store32Le(&scalar[0], cast(u32, secret.count))
    initial.update(scalar)
    initial.update(secret)
    store32Le(&scalar[0], cast(u32, associatedData.count))
    initial.update(scalar)
    initial.update(associatedData)
    try initial.finalize(seed)

    // Each block is written before it can be referenced in the first pass.
    let memorySize = blockCount * Argon2BlockSize
    let blocks     = cast([*] u64, Memory.alloc(memorySize))
    defer
    {
        secureClear(Swag.makeSlice(blocks, blockCount * Argon2Words))
        Memory.free(blocks, memorySize)
    }

    // The first two blocks of every lane come straight from the seed; everything
    // else is produced by the compression function.
    var origin: [Hash.Blake2bMaxDigestSize + 8] u8
    defer secureClear(origin)
    Swag.memcpy(&origin[0], &seed[0], Hash.Blake2bMaxDigestSize)
    for lane in lanes
    {
        for slot in 2
        {
            store32Le(&origin[Hash.Blake2bMaxDigestSize], cast(u32, slot))
            store32Le(&origin[Hash.Blake2bMaxDigestSize + 4], cast(u32, lane))
            let target = (lane * laneLength + slot) * Argon2Words
            try variableHash(origin, Swag.makeSlice(cast([*] u8, (blocks + target)), Argon2BlockSize))
        }
    }

    for pass in passes
    {
        for slice in Argon2SyncPoints
        {
            // The structured join is Argon2's slice boundary. No worker waits on a
            // sibling, and the owning memory stays alive until every lane is finished.
            parallel for |blocks, lanes, passes, segmentLength, laneLength, blockCount, pass, slice| lane in lanes do
                fillSegment(blocks, lanes, passes, segmentLength, laneLength, blockCount, pass, slice, lane)
        }
    }

    // The tag folds the last block of every lane together.
    var final: [Argon2Words] u64
    defer secureClear(final)
    for i in Argon2Words do
        final[i] = blocks[((lanes - 1) * laneLength + laneLength - 1) * Argon2Words + i]
    for lane in lanes - 1
    {
        let last = (lane * laneLength + laneLength - 1) * Argon2Words
        for i in Argon2Words do
            final[i] ^= blocks[last + i]
    }

    try variableHash(Swag.makeSlice(cast(const [*] u8, &final[0]), Argon2BlockSize), destination)
}
