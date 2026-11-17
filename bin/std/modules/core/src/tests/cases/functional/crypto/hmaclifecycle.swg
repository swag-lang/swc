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
