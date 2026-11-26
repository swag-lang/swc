#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let firstKey  = cast(const [..] u8, "first key")
    let secondKey = cast(const [..] u8, "second key")
    let discarded = cast(const [..] u8, "discarded prefix")
    let message   = cast(const [..] u8, "message")

    var hmac = Crypto.HmacSha256.create(firstKey)
    hmac.update(discarded)
    hmac.reset(secondKey)
    hmac.update(message)
    let resetDigest = hmac.finalize()

    Swag.require(Slice.equals(resetDigest, Crypto.HmacSha256.compute(secondKey, message)))
    Swag.require(not hmac.initialized)

    hmac.reset(secondKey)
    hmac.clear()
    Swag.require(not hmac.initialized)
}

#test
{
    let empty = cast(const [..] u8, "")
    var hmac: Crypto.HmacSha256

    let updateBeforeReset = Swag.catchPanic(func|&hmac, empty|()
    {
        hmac.update(empty)
    })
    let finalizeBeforeReset = Swag.catchPanic(func|&hmac|()
    {
        discard hmac.finalize()
    })

    Swag.require(updateBeforeReset.raised and updateBeforeReset.message() == "HMAC-SHA-256 needs an initialized sequence")
    Swag.require(finalizeBeforeReset.raised and finalizeBeforeReset.message() == "HMAC-SHA-256 needs an initialized sequence")
}

func(Hmac) verifySha2HmacLifecycle()
{
    var longKey: [131] u8
    Memory.set(longKey.buffer, 0xAA_u8, longKey.count)
    let message  = cast(const [..] u8, "Test Using Larger Than Block-Size Key - Hash Key First")
    let shortKey = cast(const [..] u8, "Jefe")

    var hmac = Hmac.create(longKey)
    hmac.update(message)
    hmac.update(message)
    hmac.reset(shortKey)
    hmac.update(message[until 7])
    hmac.update(message[7 until message.count])
    Swag.require(Crypto.constantTimeEqual(hmac.finalize(), Hmac.compute(shortKey, message)))

    let storage = Swag.makeSlice(cast(const [*] u8, &hmac), #sizeof(Hmac))
    for byte in storage
    {
        Swag.require(byte == 0)
    }

    hmac.reset(longKey)
    hmac.update(message)
    hmac.clear()
    for byte in storage
    {
        Swag.require(byte == 0)
    }

    hmac.reset(longKey)
    hmac.update(message)
    Swag.require(Crypto.constantTimeEqual(hmac.finalize(), Hmac.compute(longKey, message)))
}

#test
{
    verifySha2HmacLifecycle'Crypto.HmacSha224()
    verifySha2HmacLifecycle'Crypto.HmacSha256()
    verifySha2HmacLifecycle'Crypto.HmacSha384()
    verifySha2HmacLifecycle'Crypto.HmacSha512()
}
