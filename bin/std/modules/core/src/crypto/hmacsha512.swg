#global public
#global namespace Crypto

// Stores an HMAC-SHA-512 result as 64 bytes in network order.
alias HmacSha512Digest = [64] u8

// Stores an HMAC-SHA-384 result as 48 bytes in network order.
alias HmacSha384Digest = [48] u8

private func sha512DigestBytes(digest: Hash.Sha512.Digest)->HmacSha512Digest
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 8 do
            result[index * 8 + byte] = Math.byteAt(digest[index], 7 - byte)
    }

    return result
}

private func sha384DigestBytes(digest: Hash.Sha384.Digest)->HmacSha384Digest
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 8 do
            result[index * 8 + byte] = Math.byteAt(digest[index], 7 - byte)
    }

    return result
}

// Computes HMAC-SHA-512 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy, Swag.Opaque]
public struct HmacSha512
{
    inner:       Hash.Sha512
    outer:       Hash.Sha512
    initialized: bool
}

public impl HmacSha512
{
    // Creates an initialized HMAC-SHA-512 sequence for `key`.
    func create(key: const [..] u8)->HmacSha512
    {
        var result: #returntype
        result.reset(key)
        return result
    }

    // Replaces any previous keyed state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8)
    {
        .clear()
        var normalized: [Hash.Sha512BlockSize] u8
        if key.count > Hash.Sha512BlockSize
        {
            var hashed = sha512DigestBytes(Hash.Sha512.compute(key))
            Swag.memcpy(&normalized[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif key.count
        {
            Swag.memcpy(&normalized[0], key.buffer, key.count)
        }

        var innerPad: [Hash.Sha512BlockSize] u8
        var outerPad: [Hash.Sha512BlockSize] u8
        for index in Hash.Sha512BlockSize
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
        Swag.assert(.initialized, "HMAC-SHA-512 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    mtd finalize()->HmacSha512Digest
    {
        Swag.assert(.initialized, "HMAC-SHA-512 needs an initialized sequence")
        var innerHash = sha512DigestBytes(.inner.finalize())
        .outer.update(innerHash)
        let result = sha512DigestBytes(.outer.finalize())
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

    // Computes HMAC-SHA-512 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha512Digest
    {
        var hmac = HmacSha512.create(key)
        hmac.update(data)
        return hmac.finalize()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop() => .clear()
}

// Computes HMAC-SHA-384 incrementally while keeping its keyed state opaque.
#[Swag.NoCopy, Swag.Opaque]
public struct HmacSha384
{
    inner:       Hash.Sha384
    outer:       Hash.Sha384
    initialized: bool
}

public impl HmacSha384
{
    // Creates an initialized HMAC-SHA-384 sequence for `key`.
    func create(key: const [..] u8)->HmacSha384
    {
        var result: #returntype
        result.reset(key)
        return result
    }

    // Replaces any previous keyed state and starts a new sequence for `key`.
    mtd reset(key: const [..] u8)
    {
        .clear()
        var normalized: [Hash.Sha512BlockSize] u8
        if key.count > Hash.Sha512BlockSize
        {
            var hashed = sha384DigestBytes(Hash.Sha384.compute(key))
            Swag.memcpy(&normalized[0], &hashed[0], #sizeof(hashed))
            secureClear(hashed)
        }
        elif key.count
        {
            Swag.memcpy(&normalized[0], key.buffer, key.count)
        }

        var innerPad: [Hash.Sha512BlockSize] u8
        var outerPad: [Hash.Sha512BlockSize] u8
        for index in Hash.Sha512BlockSize
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
        Swag.assert(.initialized, "HMAC-SHA-384 needs an initialized sequence")
        .inner.update(data)
    }

    // Finalizes the sequence, returns its authentication code, and clears the keyed state.
    mtd finalize()->HmacSha384Digest
    {
        Swag.assert(.initialized, "HMAC-SHA-384 needs an initialized sequence")
        var innerHash = sha384DigestBytes(.inner.finalize())
        .outer.update(innerHash)
        let result = sha384DigestBytes(.outer.finalize())
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

    // Computes HMAC-SHA-384 for `data` in one operation.
    func compute(key, data: const [..] u8)->HmacSha384Digest
    {
        var hmac = HmacSha384.create(key)
        hmac.update(data)
        return hmac.finalize()
    }

    // Clears keyed state when this value leaves scope.
    mtd opDrop() => .clear()
}
