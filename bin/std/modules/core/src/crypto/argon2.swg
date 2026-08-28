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
        data[i] = cast(u8) ((value >> cast(u32) (i * 8)) & 0xFF)
}

// Argon2's variant of the BLAKE2b mixing function. The extra multiplication is
// what makes a memory-bound implementation the fastest one.
#[Swag.Inline]
private func mixBlock(block: [*] u64, a, b, c, d: u64)
{
    block[a] += block[b] + 2 * truncate32(block[a]) * truncate32(block[b])
    block[d] = @ror(block[d] ^ block[a], 32'u8)
    block[c] += block[d] + 2 * truncate32(block[c]) * truncate32(block[d])
    block[b] = @ror(block[b] ^ block[c], 24'u8)
    block[a] += block[b] + 2 * truncate32(block[a]) * truncate32(block[b])
    block[d] = @ror(block[d] ^ block[a], 16'u8)
    block[c] += block[d] + 2 * truncate32(block[c]) * truncate32(block[d])
    block[b] = @ror(block[b] ^ block[c], 63'u8)
}

// Applies the Argon2 permutation to the sixteen words addressed by `base` and
// `stride`. A row uses a stride of two, a column a stride of sixteen, which is
// what makes the compression function diffuse across the whole block.
private func permute(block: [*] u64, base, stride: u64)
{
    var index: [16] u64
    for i in 16 do
        index[i] = base + (i / 2) * stride + (i % 2)

    mixBlock(block, index[0], index[4], index[8], index[12])
    mixBlock(block, index[1], index[5], index[9], index[13])
    mixBlock(block, index[2], index[6], index[10], index[14])
    mixBlock(block, index[3], index[7], index[11], index[15])
    mixBlock(block, index[0], index[5], index[10], index[15])
    mixBlock(block, index[1], index[6], index[11], index[12])
    mixBlock(block, index[2], index[7], index[8], index[13])
    mixBlock(block, index[3], index[4], index[9], index[14])
}

// Argon2's compression function. Writes `G(x, y)` to `destination`, or XORs it
// into `destination` when `accumulate` is set, which is what the second and
// later passes do.
private func compress(destination: [*] u64, x, y: const [*] u64, accumulate: bool)
{
    var mixed:  [Argon2Words] u64
    var result: [Argon2Words] u64
    for i in Argon2Words
    {
        mixed[i]  = x[i] ^ y[i]
        result[i] = mixed[i]
    }

    for i in 8 do
        permute(&result[0], i * 16, 2)
    for i in 8 do
        permute(&result[0], i * 2, 16)

    for i in Argon2Words
    {
        let value = result[i] ^ mixed[i]
        destination[i] = accumulate ? destination[i] ^ value : value
    }

    secureClear(mixed)
    secureClear(result)
}

// RFC 9106 variable-length hash `H'`. BLAKE2b caps its digest at 64 bytes, so a
// longer request chains 64-byte digests and keeps 32 bytes of each.
private func variableHash(input: const [..] u8, destination: [..] u8) fail
{
    var prefix: [4] u8
    store32Le(&prefix[0], cast(u32) @countof(destination))

    if @countof(destination) <= Hash.Blake2bMaxDigestSize
    {
        var hash = try Hash.Blake2b.create(@countof(destination))
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
    while @countof(destination) - written > Hash.Blake2bMaxDigestSize
    {
        @memcpy(@dataof(destination) + written, &current[0], strideSize)
        written += strideSize
        if @countof(destination) - written > Hash.Blake2bMaxDigestSize do
            try Hash.Blake2b.compute(current, current)
    }

    let remaining = @countof(destination) - written
    var tail: [Hash.Blake2bMaxDigestSize] u8
    defer secureClear(tail)
    try Hash.Blake2b.compute(current, tail[0 until remaining])
    @memcpy(@dataof(destination) + written, &tail[0], remaining)
}

// Regenerates the block of pseudo-random addresses used by the data-independent
// passes, then reports the value for `offset`.
private func nextAddresses(addresses, input: [*] u64, zero: const [*] u64)
{
    input[6] += 1
    compress(addresses, zero, input, false)
    compress(addresses, zero, addresses, false)
}

// Maps a pseudo-random value onto a block that is already final, following the
// RFC 9106 indexing rules. `index` counts from the start of the current segment,
// not from the start of the lane. `sameLane` selects the larger window that only
// the current lane may use, because its recent blocks are already final.
private func referenceIndex(random: u64, pass, slice, index, segmentLength, laneLength: u64, sameLane: bool)->u64
{
    var areaSize: u64
    if !pass
    {
        if !slice do
            areaSize = index - 1
        elif sameLane do
            areaSize = slice * segmentLength + index - 1
        else do
            areaSize = slice * segmentLength - (index ? 0 : 1)
    }
    elif sameLane do
        areaSize = laneLength - segmentLength + index - 1
    else do
        areaSize = laneLength - segmentLength - (index ? 0 : 1)

    // The squared scaling biases the choice towards recent blocks, which is what
    // keeps a low-memory attacker recomputing.
    let low      = truncate32(random)
    let scaled   = (low * low) >> 32
    let relative = areaSize - 1 - ((areaSize * scaled) >> 32)

    var start = 0'u64
    if pass and slice != Argon2SyncPoints - 1 do
        start = (slice + 1) * segmentLength
    return (start + relative) % laneLength
}

// Derives `destination` with Argon2id, RFC 9106.
//
// Argon2id spends the first half of its first pass on data-independent
// addressing and everything after it on data-dependent addressing, which is what
// gives it both side-channel resistance and resistance to time-memory tradeoffs.
// It is the variant to choose unless an existing format demands another one.
//
// `salt` holds at least 8 bytes and should hold 16. `destination` holds at least
// 4 bytes. `parameters.memoryKib` is at least eight times `parameters.parallelism`,
// and the derivation allocates that many kibibytes.
//
// The same password, salt, parameters, and destination length always produce the
// same bytes, on every platform.
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

// Derives `destination` with Argon2id, additionally binding a secret and an
// associated-data string into the derivation.
//
// `secret` is the RFC 9106 key input: a value the verifier holds but the
// password database does not, at most 64 bytes. `associatedData` binds a context
// such as a user identifier. Both are optional, and both must be reproduced
// exactly to reproduce the tag.
public func argon2id(password, salt, secret, associatedData: const [..] u8, parameters: Argon2Parameters, destination: [..] u8) fail
{
    if @countof(destination) < Argon2MinTagSize do
        fail Errors.BadParameterError{"Argon2 needs a tag of at least 4 bytes"}
    if @countof(salt) < Argon2MinSaltSize do
        fail Errors.BadParameterError{"Argon2 needs a salt of at least 8 bytes"}
    if !parameters.parallelism or parameters.parallelism > 0xFF_FFFF do
        fail Errors.BadParameterError{"Argon2 needs 1 to 16777215 lanes"}
    if !parameters.iterations do
        fail Errors.BadParameterError{"Argon2 needs at least one pass"}
    if parameters.memoryKib < 8 * parameters.parallelism do
        fail Errors.BadParameterError{"Argon2 needs at least eight kibibytes of memory per lane"}
    if @countof(secret) > Hash.Blake2bMaxKeySize do
        fail Errors.BadParameterError{"Argon2 accepts a secret of at most 64 bytes"}

    let lanes         = cast(u64) parameters.parallelism
    let passes        = cast(u64) parameters.iterations
    let segmentLength = cast(u64) parameters.memoryKib / (Argon2SyncPoints * lanes)
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
    store32Le(&scalar[0], cast(u32) @countof(destination))
    initial.update(scalar)
    store32Le(&scalar[0], parameters.memoryKib)
    initial.update(scalar)
    store32Le(&scalar[0], parameters.iterations)
    initial.update(scalar)
    store32Le(&scalar[0], Argon2Version)
    initial.update(scalar)
    store32Le(&scalar[0], Argon2TypeId)
    initial.update(scalar)
    store32Le(&scalar[0], cast(u32) @countof(password))
    initial.update(scalar)
    initial.update(password)
    store32Le(&scalar[0], cast(u32) @countof(salt))
    initial.update(scalar)
    initial.update(salt)
    store32Le(&scalar[0], cast(u32) @countof(secret))
    initial.update(scalar)
    initial.update(secret)
    store32Le(&scalar[0], cast(u32) @countof(associatedData))
    initial.update(scalar)
    initial.update(associatedData)
    try initial.finalize(seed)

    var memory: Array'u64
    memory.resize(blockCount * Argon2Words)
    defer secureClear(memory.toSlice())
    let blocks = memory.buffer!

    // The first two blocks of every lane come straight from the seed; everything
    // else is produced by the compression function.
    var origin: [Hash.Blake2bMaxDigestSize + 8] u8
    defer secureClear(origin)
    @memcpy(&origin[0], &seed[0], Hash.Blake2bMaxDigestSize)
    for lane in lanes
    {
        for slot in 2
        {
            store32Le(&origin[Hash.Blake2bMaxDigestSize], cast(u32) slot)
            store32Le(&origin[Hash.Blake2bMaxDigestSize + 4], cast(u32) lane)
            let target = (lane * laneLength + slot) * Argon2Words
            try variableHash(origin, @mkslice(cast([*] u8) (blocks + target), Argon2BlockSize))
        }
    }

    var zero:      [Argon2Words] u64
    var input:     [Argon2Words] u64
    var addresses: [Argon2Words] u64
    defer secureClear(input)
    defer secureClear(addresses)

    for pass in passes
    {
        for slice in Argon2SyncPoints
        {
            for lane in lanes
            {
                // Argon2id takes its addresses from a counter for the first half
                // of the first pass, and from the previous block afterwards.
                let independent = !pass and slice < Argon2SyncPoints / 2
                if independent
                {
                    @memset(&input[0], 0, Argon2BlockSize)
                    input[0] = pass
                    input[1] = lane
                    input[2] = slice
                    input[3] = blockCount
                    input[4] = passes
                    input[5] = Argon2TypeId
                }

                var start = 0'u64
                if !pass and !slice
                {
                    start = 2
                    if independent do
                        nextAddresses(&addresses[0], &input[0], &zero[0])
                }

                var previous = lane * laneLength + (slice * segmentLength + start + laneLength - 1) % laneLength
                for step in start until segmentLength
                {
                    let index   = slice * segmentLength + step
                    let current = lane * laneLength + index

                    var random: u64
                    if independent
                    {
                        if step % Argon2AddressCount == 0 do
                            nextAddresses(&addresses[0], &input[0], &zero[0])
                        random = addresses[step % Argon2AddressCount]
                    }
                    else do
                        random = blocks[previous * Argon2Words]

                    // The first slice of the first pass has nothing to reference
                    // in another lane yet.
                    var referenceLane = (random >> 32) % lanes
                    if !pass and !slice do
                        referenceLane = lane

                    let offset    = referenceIndex(random, pass, slice, step, segmentLength, laneLength, referenceLane == lane)
                    let reference = referenceLane * laneLength + offset
                    compress(blocks + current * Argon2Words, blocks + previous * Argon2Words, blocks + reference * Argon2Words, pass != 0)
                    previous = current
                }
            }
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

    try variableHash(@mkslice(cast(const [*] u8) &final[0], Argon2BlockSize), destination)
}
