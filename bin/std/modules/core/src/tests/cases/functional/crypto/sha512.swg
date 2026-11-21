#global if #command == Swag.CompilerCommand.Test
#global private

func sha512HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func sha512HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((sha512HexDigit(text[index]) << 4) | sha512HexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

func sha512DigestBytes(digest: Hash.Sha512.Digest)->[64] u8
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 8 do
            result[index * 8 + byte] = Math.byteAt(digest[index], 7 - byte)
    }

    return result
}

func sha384DigestBytes(digest: Hash.Sha384.Digest)->[48] u8
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 8 do
            result[index * 8 + byte] = Math.byteAt(digest[index], 7 - byte)
    }

    return result
}

#test
{
    let empty512 = sha512HexBytes("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
    let abc512   = sha512HexBytes("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    let empty384 = sha512HexBytes("38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b")
    let abc384   = sha512HexBytes("cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")

    Swag.require(Crypto.constantTimeEqual(sha512DigestBytes(Hash.Sha512.compute("")), empty512.toSlice()))
    Swag.require(Crypto.constantTimeEqual(sha512DigestBytes(Hash.Sha512.compute("abc")), abc512.toSlice()))
    Swag.require(Crypto.constantTimeEqual(sha384DigestBytes(Hash.Sha384.compute("")), empty384.toSlice()))
    Swag.require(Crypto.constantTimeEqual(sha384DigestBytes(Hash.Sha384.compute("abc")), abc384.toSlice()))
}

#test
{
    var input: [400] u8
    for index in input.count do
        input[index] = cast(u8, ((index * 29 + 7) & 0xFF))

    for split in [0'u64, 1, 111, 112, 113, 127, 128, 129, 255, 256, 399, 400]
    {
        var sha512: Hash.Sha512
        sha512.update(input[until split])
        sha512.update(input[split to])
        let expected512 = Hash.Sha512.compute(input)
        Swag.require(Crypto.constantTimeEqual(sha512DigestBytes(sha512.finalize()), sha512DigestBytes(expected512)))

        var sha384: Hash.Sha384
        sha384.update(input[until split])
        sha384.update(input[split to])
        let expected384 = Hash.Sha384.compute(input)
        Swag.require(Crypto.constantTimeEqual(sha384DigestBytes(sha384.finalize()), sha384DigestBytes(expected384)))
    }
}

#test
{
    let key         = cast(const [..] u8, "Jefe")
    let data        = cast(const [..] u8, "what do ya want for nothing?")
    let expected512 = sha512HexBytes("164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737")
    let expected384 = sha512HexBytes("af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649")
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha512.compute(key, data), expected512.toSlice()))
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha384.compute(key, data), expected384.toSlice()))

    var incremental = Crypto.HmacSha512.create(key)
    incremental.update(data[until 9])
    incremental.update(data[9 to])
    Swag.require(Crypto.constantTimeEqual(incremental.finalize(), expected512.toSlice()))
    Swag.require(not incremental.initialized)
}

#test
{
    var key: [131] u8
    Memory.set(key.buffer, 0xAA'u8, key.count)
    let data        = cast(const [..] u8, "Test Using Larger Than Block-Size Key - Hash Key First")
    let expected512 = sha512HexBytes("80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598")
    let expected384 = sha512HexBytes("4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952")
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha512.compute(key, data), expected512.toSlice()))
    Swag.require(Crypto.constantTimeEqual(Crypto.HmacSha384.compute(key, data), expected384.toSlice()))
}
