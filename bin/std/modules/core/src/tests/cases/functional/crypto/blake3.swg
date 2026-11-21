#global if #command == Swag.CompilerCommand.Test
#global private

func blake3HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func blake3HexBytes(text: string)->Array'u8
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0'u64
    while index + 1 < text.count
    {
        result.add(cast(u8, (blake3HexDigit(text[index]) << 4) | blake3HexDigit(text[index + 1])))
        index += 2
    }

    return result
}

func blake3Pattern(length: u64)->Array'u8
{
    var result: #returntype
    result.resize(length)
    for index in length do
        result[index] = cast(u8, index % 251)
    return result
}

func assertBlake3(input: const [..] u8, expected: string)
{
    let reference = blake3HexBytes(expected)
    var actual: [32] u8
    expect Hash.Blake3.compute(input, actual)
    Swag.require(Crypto.constantTimeEqual(actual, reference.toSlice()))
}

#test
{
    // Official BLAKE3 vectors cover empty input and the 64-byte block boundary.
    assertBlake3("", "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
    assertBlake3("abc", "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85")
    let input63 = blake3Pattern(63)
    assertBlake3(input63.toSlice(), "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b")
    let input64 = blake3Pattern(64)
    assertBlake3(input64.toSlice(), "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98")
    let input65 = blake3Pattern(65)
    assertBlake3(input65.toSlice(), "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee")
}

#test
{
    // Official vectors exercise a full chunk, a partial following chunk, and tree reduction.
    let input1023 = blake3Pattern(1023)
    assertBlake3(input1023.toSlice(), "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11")
    let input1024 = blake3Pattern(1024)
    assertBlake3(input1024.toSlice(), "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7")
    let input1025 = blake3Pattern(1025)
    assertBlake3(input1025.toSlice(), "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444")
    let input2049 = blake3Pattern(2049)
    assertBlake3(input2049.toSlice(), "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030")
}

#test
{
    // Official keyed and context-derivation vectors use the published 32-byte key and context.
    let key = "whats the Elvish word for friend"
    var emptyDigest: [32] u8
    expect Hash.Blake3.computeKeyed(key, "", emptyDigest)
    let keyed = blake3HexBytes("92b2b75604ed3c761f9d6f62392c8a9227ad0ea3f09573e783f1498a4ed60d26")
    Swag.require(Crypto.constantTimeEqual(emptyDigest, keyed.toSlice()))

    let context = "BLAKE3 2019-12-27 16:29:52 test vectors context"
    var derived: [32] u8
    expect Hash.Blake3.deriveKey(context, "", derived)
    let deriveExpected = blake3HexBytes("2cc39783c223154fea8dfb7c1b1660f2ac2dcbd1c1de8277b0b0dd39b7e50d7d")
    Swag.require(Crypto.constantTimeEqual(derived, deriveExpected.toSlice()))

    let input = blake3Pattern(1025)
    var keyedInput: [32] u8
    expect Hash.Blake3.computeKeyed(key, input.toSlice(), keyedInput)
    let keyedExpected = blake3HexBytes("357dc55de0c7e382c900fd6e320acc04146be01db6a8ce7210b7189bd664ea69")
    Swag.require(Crypto.constantTimeEqual(keyedInput, keyedExpected.toSlice()))
}

#test
{
    // Streaming boundaries preserve the same tree and root output as the one-shot API.
    let input = blake3Pattern(4097)
    var expected: [32] u8
    expect Hash.Blake3.compute(input.toSlice(), expected)
    for split in [1'u64, 63, 64, 65, 1023, 1024, 1025, 2048, 4096]
    {
        var hash   = Hash.Blake3.create()
        var offset = 0'u64
        while offset < input.count
        {
            let count = Math.min(split, input.count - offset)
            hash.update(input[offset until offset + count])
            offset += count
        }

        var streamed: [32] u8
        expect hash.finalize(streamed)
        Swag.require(Crypto.constantTimeEqual(streamed, expected))
    }

    // This published vector crosses the parallel threshold and checks multi-level tree merging.
    let large = blake3Pattern(102400)
    assertBlake3(large.toSlice(), "bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085")
}

#test
{
    var badKey:   [31] u8
    var digest:   [32] u8
    var keyError: Swag.Error
    discard catch Hash.Blake3.computeKeyed(badKey, "", digest) as keyError
    Swag.require(keyError.value() is Errors.BadParameterError)

    var hash = Hash.Blake3.create()
    hash.clear()
    var finalizeError: Swag.Error
    discard catch hash.finalize(digest) as finalizeError
    Swag.require(finalizeError.value() is Errors.BadParameterError)
}
