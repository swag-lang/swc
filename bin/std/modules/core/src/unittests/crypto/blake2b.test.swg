#global if #command == Swag.CompilerCommand.Test
#global private

// Parses a lowercase hexadecimal literal into bytes, so the RFC 7693 vectors can
// be written exactly as the specification prints them.
func hexBytes(text: string)->Array'u8
{
    var result: retval
    result.reserve(@countof(text) / 2)
    var index = 0'u64
    while index + 1 < @countof(text)
    {
        result.add(cast(u8) ((hexDigit(text[index]) << 4) | hexDigit(text[index + 1])))
        index += 2
    }

    return result
}

func hexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    return (value - 'a') + 10
}

func assertBlake2b(data: const [..] u8, expected: string)
{
    let reference = hexBytes(expected)

    var oneShot: Array'u8
    oneShot.resize(reference.count)
    expect Hash.Blake2b.compute(data, oneShot.toSlice())
    @assert(Crypto.constantTimeEqual(oneShot.toSlice(), reference.toSlice()))

    // The incremental path must agree with the one-shot path, including when the
    // input is split across a block boundary.
    var streamed: Array'u8
    streamed.resize(reference.count)
    var hash = expect Hash.Blake2b.create(reference.count)
    var offset = 0'u64
    while offset < @countof(data)
    {
        let chunk = Math.min(@countof(data) - offset, 7'u64)
        hash.update(data[offset until offset + chunk])
        offset += chunk
    }

    expect hash.finalize(streamed.toSlice())
    @assert(Crypto.constantTimeEqual(streamed.toSlice(), reference.toSlice()))
}

#test
{
    // RFC 7693 appendix A, and the reference implementation's empty-input vector.
    assertBlake2b("", "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce")
    assertBlake2b("abc", "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
}

#test
{
    // A digest length is bound into the state, so a shorter digest is not a
    // prefix of a longer one.
    var short:  [32] u8
    var long:   [64] u8
    expect Hash.Blake2b.compute("abc", short)
    expect Hash.Blake2b.compute("abc", long)
    @assert(!Crypto.constantTimeEqual(short, long[0 until 32]))

    // BLAKE2b-256 of "abc", from the reference implementation.
    let expected = hexBytes("bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319")
    @assert(Crypto.constantTimeEqual(short, expected.toSlice()))
}

#test
{
    // Keyed mode prepends a padded key block, so it never matches the unkeyed
    // digest of the same message.
    let key: [4] u8 = [1, 2, 3, 4]
    var keyed:   [32] u8
    var unkeyed: [32] u8
    expect Hash.Blake2b.computeKeyed(key, "abc", keyed)
    expect Hash.Blake2b.compute("abc", unkeyed)
    @assert(!Crypto.constantTimeEqual(keyed, unkeyed))

    // RFC 7693 appendix E keyed vector: key 00..3f, input 00, 64-byte digest.
    var fullKey: [64] u8
    for [i] in 64 do
        fullKey[i] = cast(u8) i
    let input: [1] u8 = [0]
    var digest: [64] u8
    expect Hash.Blake2b.computeKeyed(fullKey, input, digest)
    let expected = hexBytes("961f6dd1e4dd30f63901690c512e78e4b45e4742ed197c3c5e45c549fd25f2e4187b0bc9fe30492b16b0d0bc4ef9b0f34c7003fac09a5ef1532e69430234cebd")
    @assert(Crypto.constantTimeEqual(digest, expected.toSlice()))
}

#test
{
    // The digest length is validated at both ends of the sequence.
    discard catch Hash.Blake2b.create(0) as emptyDigest
    @assert(emptyDigest != null)
    discard catch Hash.Blake2b.create(Hash.Blake2bMaxDigestSize + 1) as hugeDigest
    @assert(hugeDigest != null)

    var hash = expect Hash.Blake2b.create(32)
    var wrong: [16] u8
    discard catch hash.finalize(wrong) as lengthMismatch
    @assert(lengthMismatch != null)

    var oversizedKey: [Hash.Blake2bMaxKeySize + 1] u8
    var digest: [32] u8
    discard catch Hash.Blake2b.computeKeyed(oversizedKey, "abc", digest) as hugeKey
    @assert(hugeKey != null)
}
