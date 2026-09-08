#global if #command == Swag.CompilerCommand.Test
#global private

func filledBytes(count: u64, value: u8)->Array'u8
{
    var result: retval
    result.resize(count)
    for i in count do
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
    Swag.assert(Crypto.constantTimeEqual(tag, expected))
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
    Swag.assert(Crypto.constantTimeEqual(baseline, repeated))

    var moreMemory: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 64, iterations: 2, parallelism: 1}, moreMemory)
    Swag.assert(!Crypto.constantTimeEqual(baseline, moreMemory))

    var morePasses: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 3, parallelism: 1}, morePasses)
    Swag.assert(!Crypto.constantTimeEqual(baseline, morePasses))

    var moreLanes: [32] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 2}, moreLanes)
    Swag.assert(!Crypto.constantTimeEqual(baseline, moreLanes))

    var otherPassword: [32] u8
    expect Crypto.argon2id("passphrasf", salt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 1}, otherPassword)
    Swag.assert(!Crypto.constantTimeEqual(baseline, otherPassword))

    let otherSalt = filledBytes(16, 0x2B)
    var otherSaltTag: [32] u8
    expect Crypto.argon2id("passphrase", otherSalt.toSlice(), {memoryKib: 32, iterations: 2, parallelism: 1}, otherSaltTag)
    Swag.assert(!Crypto.constantTimeEqual(baseline, otherSaltTag))
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
    Swag.assert(!Crypto.constantTimeEqual(short, long[0 until 16]))

    var repeatedLong: [100] u8
    expect Crypto.argon2id("passphrase", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, repeatedLong)
    Swag.assert(Crypto.constantTimeEqual(long, repeatedLong))
}

#test
{
    // Every parameter that would make a derivation meaningless is rejected
    // before any memory is allocated.
    let salt = filledBytes(16, 0x11)
    var tag: [32] u8

    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 32, iterations: 0, parallelism: 1}, tag) as noPass
    Swag.assert(noPass != null)

    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 0}, tag) as noLane
    Swag.assert(noLane != null)

    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 4, iterations: 1, parallelism: 1}, tag) as tooLittleMemory
    Swag.assert(tooLittleMemory != null)

    let shortSalt = filledBytes(Crypto.Argon2MinSaltSize - 1, 0x11)
    discard catch Crypto.argon2id("password", shortSalt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, tag) as shortSaltError
    Swag.assert(shortSaltError != null)

    var shortTag: [Crypto.Argon2MinTagSize - 1] u8
    discard catch Crypto.argon2id("password", salt.toSlice(), {memoryKib: 32, iterations: 1, parallelism: 1}, shortTag) as shortTagError
    Swag.assert(shortTagError != null)
}

#test
{
    // Reference tags from the Argon2 reference implementation via argon2-cffi 25.1.0.
    // Cover the serial/parallel cutoff, 127/128/129-block address windows, rounded
    // memory, and more lanes than workers. Scheduling must not change the tag.
    Swag.setWorkerCount(4)
    let lanes:    [7] u32    = [1, 3, 3, 3, 3, 3, 7]
    let memory:   [7] u32    = [516, 372, 384, 1524, 1536, 1549, 3615]
    let expected: [7][32] u8 = [
        [0x60, 0xC0, 0x4A, 0xDD, 0xEB, 0x7E, 0xE5, 0x0B, 0xB8, 0x77, 0xE0, 0x48, 0xE2, 0xE3, 0xAC, 0x7F, 0xCD, 0xDC, 0xE6, 0x7A, 0xDE, 0xF7, 0x77, 0xF1, 0x98, 0xA1, 0xB4, 0x8F, 0xDB, 0x6D, 0xA0, 0xCA],
        [0xDE, 0xFA, 0xF0, 0x1E, 0x46, 0x96, 0xBF, 0x6F, 0xC1, 0xD1, 0x9B, 0x9B, 0x03, 0x50, 0xAC, 0x17, 0x82, 0x95, 0xC1, 0x9C, 0xBF, 0x95, 0xAB, 0x36, 0x68, 0x42, 0x61, 0x45, 0x52, 0x97, 0x3C, 0x81],
        [0xA6, 0x93, 0xBC, 0xE9, 0x68, 0x33, 0xAF, 0x63, 0xD1, 0x46, 0x57, 0xDC, 0x54, 0x7A, 0xE3, 0xE3, 0xD6, 0x6A, 0x59, 0x91, 0x06, 0xCC, 0xE3, 0x71, 0x64, 0xE6, 0xA7, 0x78, 0xA0, 0xFD, 0xB6, 0xBC],
        [0x0E, 0x2D, 0xE7, 0x61, 0xD0, 0x3C, 0xB4, 0x7F, 0xE5, 0xA6, 0xF1, 0xE9, 0x4B, 0xCD, 0x18, 0x98, 0x95, 0x36, 0x1E, 0x0F, 0x59, 0x53, 0xB9, 0x93, 0xC7, 0x79, 0x1C, 0x98, 0x3B, 0x68, 0x0C, 0xE9],
        [0x3A, 0xA9, 0xC5, 0x8B, 0xA7, 0x6F, 0x56, 0xD6, 0x52, 0x48, 0xE2, 0xEA, 0x77, 0xBD, 0x4C, 0xA8, 0xEA, 0x33, 0xE3, 0xA3, 0x24, 0xE1, 0x75, 0x71, 0x8E, 0xA9, 0xF2, 0xAF, 0xF5, 0x9C, 0x7A, 0x28],
        [0x12, 0x38, 0xED, 0x42, 0xD1, 0x53, 0xDE, 0x28, 0x0D, 0xE7, 0x0B, 0x32, 0xA7, 0x50, 0x1C, 0x2C, 0xB7, 0xE1, 0x11, 0xAA, 0x7F, 0x8E, 0xF5, 0x32, 0xA2, 0x5B, 0xF4, 0xE1, 0x41, 0xA2, 0x77, 0x69],
        [0x7C, 0xAB, 0xAD, 0xC5, 0x8D, 0x4A, 0xF0, 0xDA, 0x89, 0x24, 0x11, 0x4E, 0xD4, 0x91, 0x15, 0xE3, 0x00, 0x65, 0x26, 0x52, 0x7D, 0x98, 0x8F, 0x3E, 0xC1, 0x07, 0x68, 0x00, 0x71, 0xC5, 0xF3, 0xA6]]

    for index in lanes.count
    {
        var tag: [32] u8
        expect Crypto.argon2id("parallel passphrase", "parallel salt!!!", {memoryKib: memory[index], iterations: 3, parallelism: lanes[index]}, tag)
        Swag.assert(Crypto.constantTimeEqual(tag, expected[index]))
    }

    // Derivations may themselves be children of CPU tasks. Each call owns its
    // matrix and must finish its nested partitions before publishing its result.
    var tags: [3][32] u8
    parallel for |&tags| index in 3 do
        expect Crypto.argon2id("parallel passphrase", "parallel salt!!!", {memoryKib: 1549, iterations: 3, parallelism: 3}, tags[index])
    for tag in tags do
        Swag.assert(Crypto.constantTimeEqual(tag, expected[5]))
}
