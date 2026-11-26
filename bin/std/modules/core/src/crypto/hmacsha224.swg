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
        if .initialized do
            .clear()

        var pad: [64] u8
        if key.count > pad.count
        {
            var hashed = sha2HmacDigestBytes'7(Hash.Sha224.compute(key))
            Swag.memcpy(&pad[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif key.count
        {
            Swag.memcpy(&pad[0], key.buffer, key.count)
        }

        .inner.reset()
        xorSha2HmacPad'0x36(pad.buffer)
        .inner.update(pad)

        .outer.reset()

        // Convert the inner pad into the outer pad in the same buffer.
        xorSha2HmacPad'(0x36 ^ 0x5C)(pad.buffer)
        .outer.update(pad)
        .initialized = true
        secureClear(pad)
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
        var innerHash = sha2HmacDigestBytes'7(.inner.finalize())
        .outer.update(innerHash)
        let result = sha2HmacDigestBytes'7(.outer.finalize())
        secureClear(innerHash)
        .clear()
        return result
    }

    // Clears all keyed state held by this value.
    mtd clear()
    {
        secureClear(Swag.makeSlice(cast([*] u8, me), #sizeof(HmacSha224)))
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop()
    {
        if .initialized do
            .clear()
    }

    // Computes HMAC-SHA-224 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha224Digest
    {
        var hmac = HmacSha224.create(key)
        hmac.update(data)
        return hmac.finalize()
    }
}
