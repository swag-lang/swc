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

#[Swag.Inline]
private func checkHmacSha3DigestSize(digestSize: u64) fail
{
    if digestSize != 28 and digestSize != 32 and digestSize != 48 and digestSize != 64
    {
        fail Errors.BadParameterError{"HMAC-SHA-3 digest size must be 28, 32, 48, or 64 bytes"}
    }
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
        try checkHmacSha3DigestSize(digestSize)

        .initialized = false
        .digestSize  = digestSize
        .blockSize   = 200 - 2 * digestSize
        Hash.resetHmacSha3Sponges(&.inner, &.outer, key, .blockSize, digestSize)
        .initialized = true
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
        if not .initialized
        {
            fail Errors.BadParameterError{"HMAC-SHA-3 needs an initialized sequence"}
        }

        if destination.count != .digestSize
        {
            fail Errors.BadParameterError{"HMAC-SHA-3 destination must match the configured digest size"}
        }

        Hash.finalizeHmacSha3Sponges(&.inner, &.outer, destination)
        .initialized = false
        .digestSize  = 0
        .blockSize   = 0
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        // Finalize and clear reset the digest size after wiping both sponges.
        if .digestSize
        {
            .clear()
        }
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
        try checkHmacSha3DigestSize(digestSize)

        if destination.count != digestSize
        {
            fail Errors.BadParameterError{"HMAC-SHA-3 destination must match the configured digest size"}
        }

        Hash.computeHmacSha3(key, data, destination)
    }
}
