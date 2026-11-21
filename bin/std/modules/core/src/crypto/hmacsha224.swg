#global public
#global namespace Crypto

// Stores an HMAC-SHA-224 result as 28 bytes in network order.
alias HmacSha224Digest = [28] u8

// Computes HMAC-SHA-224 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy, Swag.Opaque]
struct HmacSha224
{
    inner:       Hash.Sha224
    outer:       Hash.Sha224
    initialized: bool
}

private func sha224Bytes(digest: Hash.Sha224.Digest)->HmacSha224Digest
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 4 do
            result[index * 4 + byte] = Math.byteAt(digest[index], 3 - byte)
    }

    return result
}

impl HmacSha224
{
    // Creates an initialized HMAC-SHA-224 sequence for `key`.
    func create(key: const [..] u8)->HmacSha224
    {
        var result: #returntype
        result.reset(key)
        return result
    }

    // Replaces any previous keyed state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8)
    {
        .clear()

        var normalized: [64] u8
        if key.count > normalized.count
        {
            var hashed = sha224Bytes(Hash.Sha224.compute(key))
            Swag.memcpy(&normalized[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif key.count
        {
            Swag.memcpy(&normalized[0], key.buffer, key.count)
        }

        var innerPad: [64] u8
        var outerPad: [64] u8
        for index in 64
        {
            innerPad[index] = normalized[index] ^ 0x36
            outerPad[index] = normalized[index] ^ 0x5C
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
        Swag.assert(.initialized, "HMAC-SHA-224 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    //
    // Call [[reset]] before reusing this value.
    mtd finalize()->HmacSha224Digest
    {
        Swag.assert(.initialized, "HMAC-SHA-224 needs an initialized sequence")
        var innerHash = sha224Bytes(.inner.finalize())
        .outer.update(innerHash)
        let result = sha224Bytes(.outer.finalize())
        secureClear(innerHash)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        .inner.clear()
        .outer.clear()
        .initialized = false
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop() => .clear()

    // Computes HMAC-SHA-224 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha224Digest
    {
        var hmac = HmacSha224.create(key)
        hmac.update(data)
        return hmac.finalize()
    }
}
