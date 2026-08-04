#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func sameCryptoBytes(left, right: const [..] u8)->bool
{
    return @countof(left) == @countof(right) and
           @memcmp(@dataof(left), @dataof(right), @countof(left)) == 0
}

#test
{
    var keys: Crypto.Keys
    for [i] in 32
    {
        keys.encryption[i]     = cast(u8) i
        keys.authentication[i] = cast(u8) (255 - i)
    }

    let plain:  [6] u8 = [1, 2, 3, 4, 5, 6]
    var nonce:  [Crypto.NonceSize] u8
    var cipher: [6] u8
    var tag:    [Crypto.TagSize] u8
    expect Crypto.seal(&keys, 7, 11, plain, nonce, cipher, tag)

    var opened: [6] u8
    @assert(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened))
    @assert(sameCryptoBytes(opened, plain))

    cipher[0] ^= 1
    @assert(!(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened)))
    cipher[0]               ^= 1
    tag[Crypto.TagSize - 1] ^= 1
    @assert(!(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened)))
    tag[Crypto.TagSize - 1] ^= 1
    nonce[0]                ^= 1
    @assert(!(expect Crypto.open(&keys, 7, 11, nonce, cipher, tag, opened)))
    nonce[0] ^= 1
    @assert(!(expect Crypto.open(&keys, 8, 11, nonce, cipher, tag, opened)))
    @assert(!(expect Crypto.open(&keys, 7, 12, nonce, cipher, tag, opened)))

    let locator = Crypto.recordLocator(keys.authentication, 3, 0)
    @assert(sameCryptoBytes(locator,
                            Crypto.recordLocator(keys.authentication, 3, 0)))
    @assert(!sameCryptoBytes(locator,
                             Crypto.recordLocator(keys.authentication, 3, 1)))
    @assert(!sameCryptoBytes(locator,
                             Crypto.recordLocator(keys.authentication, 4, 0)))

    var shortNonce: [Crypto.NonceSize - 1] u8
    @assert(!(expect Crypto.open(&keys, 7, 11, shortNonce, cipher, tag, opened)))
    keys.clear()
    for byte in keys.encryption do
        @assert(byte == 0)
    for byte in keys.authentication do
        @assert(byte == 0)
}

#test
{
    var key:   [Crypto.KeySize] u8
    var nonce: [Crypto.NonceSize] u8
    for value, [i] in key do
        key[i] = cast(u8) i
    for value, [i] in nonce do
        nonce[i] = cast(u8) (i * 3)

    var plain: [137] u8
    for value, [i] in plain do
        plain[i] = cast(u8) ((i * 29 + 7) & 0xFF)
    var cipher:   [137] u8
    var reopened: [137] u8
    expect Crypto.crypt(key, nonce, plain, cipher)
    @assert(!sameCryptoBytes(cipher, plain))
    expect Crypto.crypt(key, nonce, cipher, reopened)
    @assert(sameCryptoBytes(reopened, plain))

    let password = @mkslice(cast(const [*] u8) @dataof("vault password"), 14)
    let salt     = @mkslice(cast(const [*] u8) @dataof("fixed test salt"), 15)
    var first    = expect Crypto.deriveKeys(password, salt, 2)
    var second   = expect Crypto.deriveKeys(password, salt, 2)
    @assert(sameCryptoBytes(first.encryption, second.encryption))
    @assert(sameCryptoBytes(first.authentication, second.authentication))
    @assert(!sameCryptoBytes(first.encryption, first.authentication))
    first.clear()
    second.clear()
}
