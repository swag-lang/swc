#global public
#global namespace Crypto

// Stores an HMAC-SHA-256 result as 32 bytes in network order.
alias HmacSha256Digest = [32] u8

// Computes HMAC-SHA-256 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy]
#[Swag.Opaque]
struct HmacSha256
{
    public
    {
        internal
        inner:       Hash.Sha256
        outer:       Hash.Sha256
        initialized: bool
    }
}

private func sha256Bytes(digest: Hash.Sha256.Digest)->HmacSha256Digest
{
    var result: retval
    for i in 8
    {
        let word = digest[i]
        result[i * 4 + 0] = cast(u8) ((word >> 24) & 0xFF)
        result[i * 4 + 1] = cast(u8) ((word >> 16) & 0xFF)
        result[i * 4 + 2] = cast(u8) ((word >> 8) & 0xFF)
        result[i * 4 + 3] = cast(u8) (word & 0xFF)
    }

    return result
}

public impl HmacSha256
{
    // Creates an initialized HMAC-SHA-256 sequence for `key`.
    func create(key: const [..] u8)->HmacSha256
    {
        var result: retval
        result.reset(key)
        return result
    }

    // Replaces any previous keyed state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8)
    {
        .clear()

        var normalized: [64] u8
        if @countof(key) > 64
        {
            var hashed = sha256Bytes(Hash.Sha256.compute(key))
            @memcpy(&normalized[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif @countof(key) do
            @memcpy(&normalized[0], @dataof(key), @countof(key))

        var innerPad: [64] u8
        var outerPad: [64] u8
        for i in 64
        {
            innerPad[i] = normalized[i] ^ 0x36
            outerPad[i] = normalized[i] ^ 0x5C
        }

        .inner.reset()
        .outer.reset()
        .inner.update(innerPad)
        .outer.update(outerPad)
        .initialized = true

        secureClear(normalized)
        secureClear(innerPad)
        secureClear(outerPad)
    }

    // Includes `data` in the running authentication code.
    mtd update(data: const [..] u8)
    {
        Debug.assert(.initialized, "HMAC-SHA-256 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    // Call [[reset]] before reusing this value.
    mtd finalize()->HmacSha256Digest
    {
        Debug.assert(.initialized, "HMAC-SHA-256 needs an initialized sequence")
        var innerHash = sha256Bytes(.inner.finalize())
        .outer.update(innerHash)
        let result = sha256Bytes(.outer.finalize())
        secureClear(innerHash)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        secureClear(.inner.data)
        secureClear(.inner.state)
        secureClear(.outer.data)
        secureClear(.outer.state)
        .inner.dataLength = 0
        .inner.bitLength  = 0
        .outer.dataLength = 0
        .outer.bitLength  = 0
        .initialized      = false
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        .clear()
    }

    // Computes HMAC-SHA-256 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha256Digest
    {
        var hmac = HmacSha256.create(key)
        hmac.update(data)
        return hmac.finalize()
    }
}
