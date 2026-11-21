#global public
#global namespace Crypto

// Largest supported HMAC-SHA-3 digest size in bytes.
public const HmacSha3MaxDigestSize = 64

// Computes HMAC-SHA-3 incrementally for one standard SHA-3 digest size.
#[Swag.NoCopy, Swag.Opaque]
struct HmacSha3
{
    inner:       Hash.Sha3
    outer:       Hash.Sha3
    digestSize:  u64
    blockSize:   u64
    initialized: bool
}

impl HmacSha3
{
    // Creates an initialized HMAC-SHA-3 sequence for a 28, 32, 48, or 64-byte digest.
    func create(key: const [..] u8, digestSize: u64)->HmacSha3 fail
    {
        var result: #returntype
        try result.reset(key, digestSize)
        return result
    }

    // Replaces previous keyed state and starts a new sequence for `key` and `digestSize`.
    mtd reset(key: const [..] u8, digestSize: u64) fail
    {
        if digestSize != 28 and digestSize != 32 and digestSize != 48 and digestSize != 64 do
            fail Errors.BadParameterError{"HMAC-SHA-3 digest size must be 28, 32, 48, or 64 bytes"}
        .clear()
        .digestSize = digestSize
        .blockSize  = 200 - 2 * digestSize

        var normalized: [Hash.Sha3MaxRate] u8
        if key.count > .blockSize
        {
            var keyHash = try Hash.Sha3.create(digestSize)
            keyHash.update(key)
            try keyHash.finalize(Swag.makeSlice(&normalized[0], digestSize))
            keyHash.clear()
        }
        elif key.count
        {
            Swag.memcpy(&normalized[0], key.buffer, key.count)
        }

        var innerPad: [Hash.Sha3MaxRate] u8
        var outerPad: [Hash.Sha3MaxRate] u8
        for index in .blockSize
        {
            innerPad[index] = normalized[index] ^ 0x36
            outerPad[index] = normalized[index] ^ 0x5C
        }

        try .inner.reset(digestSize)
        try .outer.reset(digestSize)
        .inner.update(Swag.makeSlice(&innerPad[0], .blockSize))
        .outer.update(Swag.makeSlice(&outerPad[0], .blockSize))
        .initialized = true
        Crypto.secureClear(normalized)
        Crypto.secureClear(innerPad)
        Crypto.secureClear(outerPad)
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Swag.assert(.initialized, "HMAC-SHA-3 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence into a destination of exactly the configured digest size.
    //
    // Clears keyed state; call [[reset]] before reusing this value.
    mtd finalize(destination: [..] u8) fail
    {
        if not .initialized do
            fail Errors.BadParameterError{"HMAC-SHA-3 needs an initialized sequence"}
        if destination.count != .digestSize do
            fail Errors.BadParameterError{"HMAC-SHA-3 destination must match the configured digest size"}

        var innerHash: [HmacSha3MaxDigestSize] u8
        defer Crypto.secureClear(innerHash)
        let innerDigest = Swag.makeSlice(&innerHash[0], .digestSize)
        try .inner.finalize(innerDigest)
        .outer.update(innerDigest)
        try .outer.finalize(destination)
        .clear()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }

    // Clears both sponge states and the selected digest parameters.
    mtd clear()
    {
        .inner.clear()
        .outer.clear()
        .digestSize  = 0
        .blockSize   = 0
        .initialized = false
    }

    // Computes HMAC-SHA-3 for `data` with the requested standard digest size.
    func compute(key, data: const [..] u8, digestSize: u64, destination: [..] u8) fail
    {
        var hmac = try HmacSha3.create(key, digestSize)
        hmac.update(data)
        try hmac.finalize(destination)
    }
}
