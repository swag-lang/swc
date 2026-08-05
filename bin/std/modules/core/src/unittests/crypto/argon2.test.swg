#global if #command == Swag.CompilerCommand.Test
#global private

func filledBytes(count: u64, value: u8)->Array'u8
{
    var result: retval
    result.resize(count)
    for [i] in count do
        result[i] = value
    return result
}

#test
{
    // RFC 9106 section 5.3, the Argon2id reference vector: p=4, t=3, m=32 KiB,
    // with a secret and associated data, over a 32-byte tag.
    let password       = filledBytes(32, 0x01)
    let salt           = filledBytes(16, 0x02)
    let secret         = filledBytes(8, 0x03)
    let associatedData = filledBytes(12, 0x04)

    var tag: [32] u8
    expect Crypto.argon2id(password.toSlice(), salt.toSlice(), secret.toSlice(), associatedData.toSlice(), {memoryKib: 32, iterations: 3, parallelism: 4}, tag)

    let expected: [32] u8 = [
        0x0D, 0x64, 0x0D, 0xF5, 0x8D, 0x78, 0x76, 0x6C,
        0x08, 0xC0, 0x37, 0xA3, 0x4A, 0x8B, 0x53, 0xC9,
        0xD0, 0x1E, 0xF0, 0x45, 0x2D, 0x75, 0xB6, 0x5E,
        0xB5, 0x25, 0x20, 0xE9, 0x6B, 0x01, 0xE6, 0x59]
    @assert(Crypto.constantTimeEqual(tag, expected))
}

#test
{
    // A derivation is reproducible, and every cost parameter separates it from
    // the others: a stored tag is only meaningful next to its parameters.
    let salt = filledBytes(16, 0x2A)

    var baseline: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 1}, baseline)

    var repeated: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 1}, repeated)
    @assert(Crypto.constantTimeEqual(baseline, repeated))

    var moreMemory: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 64, iterations: 2, parallelism: 1}, moreMemory)
    @assert(!Crypto.constantTimeEqual(baseline, moreMemory))

    var morePasses: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 3, parallelism: 1}, morePasses)
    @assert(!Crypto.constantTimeEqual(baseline, morePasses))

    var moreLanes: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 2}, moreLanes)
    @assert(!Crypto.constantTimeEqual(baseline, moreLanes))

    var otherPassword: [32] u8
    expect Crypto.argon2id("passphrasf", salt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 1}, otherPassword)
    @assert(!Crypto.constantTimeEqual(baseline, otherPassword))

    let otherSalt = filledBytes(16, 0x2B)
    var otherSaltTag: [32] u8
    expect Crypto.argon2id("passphrase", otherSalt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 1}, otherSaltTag)
    @assert(!Crypto.constantTimeEqual(baseline, otherSaltTag))
}

#test
{
    // The tag length is bound into the derivation, so a short tag is not a
    // prefix of a long one, and a tag longer than one BLAKE2b digest exercises
    // the chained variable-length hash.
    let salt = filledBytes(16, 0x07)

    var short: [16] u8
    var long:  [100] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, short)
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, long)
    @assert(!Crypto.constantTimeEqual(short, long[0 until 16]))

    var repeatedLong: [100] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, repeatedLong)
    @assert(Crypto.constantTimeEqual(long, repeatedLong))
}

#test
{
    // Every parameter that would make a derivation meaningless is rejected
    // before any memory is allocated.
    let salt = filledBytes(16, 0x11)
    var tag:  [32] u8

    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 32, iterations: 0, parallelism: 1}, tag) as noPass
    @assert(noPass != null)

    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 0}, tag) as noLane
    @assert(noLane != null)

    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 4, iterations: 1, parallelism: 1}, tag) as tooLittleMemory
    @assert(tooLittleMemory != null)

    let shortSalt = filledBytes(Crypto.Argon2MinSaltSize - 1, 0x11)
    discard catch Crypto.argon2id("password", shortSalt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, tag) as shortSaltError
    @assert(shortSaltError != null)

    var shortTag: [Crypto.Argon2MinTagSize - 1] u8
    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, shortTag) as shortTagError
    @assert(shortTagError != null)
}
