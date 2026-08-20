#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func base64Reference(bytes: const [..] u8)->String
{
    const Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var result: retval
    var index = 0'u64
    while index + 3 <= @countof(bytes)
    {
        let group = (cast(u32) bytes[index] << 16) | (cast(u32) bytes[index + 1] << 8) | bytes[index + 2]
        result.append(Alphabet[group >> 18])
        result.append(Alphabet[(group >> 12) & 63])
        result.append(Alphabet[(group >> 6) & 63])
        result.append(Alphabet[group & 63])
        index += 3
    }

    if @countof(bytes) - index == 1
    {
        let group = cast(u32) bytes[index] << 16
        result.append(Alphabet[group >> 18])
        result.append(Alphabet[(group >> 12) & 63])
        result.append('='u8)
        result.append('='u8)
    }
    elif @countof(bytes) - index == 2
    {
        let group = (cast(u32) bytes[index] << 16) | (cast(u32) bytes[index + 1] << 8)
        result.append(Alphabet[group >> 18])
        result.append(Alphabet[(group >> 12) & 63])
        result.append(Alphabet[(group >> 6) & 63])
        result.append('='u8)
    }

    return result
}

// Encoding covers every padding shape, and decoding reads its own output back.
#test
{
    @assert(Base64.encode(cast(const [..] u8) "").isEmpty())
    @assert(Base64.encode(cast(const [..] u8) "f") == "Zg==")
    @assert(Base64.encode(cast(const [..] u8) "fo") == "Zm8=")
    @assert(Base64.encode(cast(const [..] u8) "foo") == "Zm9v")
    @assert(Base64.encode(cast(const [..] u8) "foob") == "Zm9vYg==")
    @assert(Base64.encode(cast(const [..] u8) "fooba") == "Zm9vYmE=")
    @assert(Base64.encode(cast(const [..] u8) "foobar") == "Zm9vYmFy")

    let bytes = expect Base64.decode("Zm9vYmFy")
    @assert(cast(string) bytes.toSlice() == "foobar")
}

// Decoding accepts the forms real documents carry: padding, no padding, the URL-safe alphabet,
// and embedded white space.
#test
{
    @assert(cast(string) (expect Base64.decode("Zm9vYg==")).toSlice() == "foob")
    @assert(cast(string) (expect Base64.decode("Zm9vYg")).toSlice() == "foob")
    @assert(cast(string) (expect Base64.decode("Zm9v\r\n YmFy")).toSlice() == "foobar")

    // `+/` and `-_` spell the same two sextets.
    let standard = expect Base64.decode("+/8=")
    let urlSafe  = expect Base64.decode("-_8")
    @assert(standard.count == 2 and urlSafe.count == 2)
    @assert(standard[0] == urlSafe[0] and standard[1] == urlSafe[1])
}

// Malformed input is reported rather than decoded into something else.
#test
{
    discard catch Base64.decode("Zm9v!") as badCharacter
    @assert(badCharacter != null)
    discard catch Base64.decode("Z") as truncated
    @assert(truncated != null)
    discard catch Base64.decode("Zg==Zg") as afterPadding
    @assert(afterPadding != null)
}

// Every short tail crosses the 12/16-byte packed boundaries and round-trips
// against an independent scalar encoder.
#test
{
    var input: [129] u8
    for i in 129 do
        input[i] = cast(u8) ((i * 73 + 19) & 0xFF)

    for length in 130
    {
        let expected = base64Reference(input[until length])
        let encoded  = Base64.encode(input[until length])
        @assert(encoded == expected)
        let decoded = expect Base64.decode(encoded)
        @assert(Slice.equals(decoded.toSlice(), input[until length]))
    }

    let spaced = expect Base64.decode("QUJDREVGR0hJSktM\r\nTU5PUA==")
    @assert(cast(string) spaced.toSlice() == "ABCDEFGHIJKLMNOP")
    let urlSafe = expect Base64.decode("LS0tX19fLS0tX19fLS0tX19f")
    @assert(cast(string) urlSafe.toSlice() == "---___---___---___")
}
