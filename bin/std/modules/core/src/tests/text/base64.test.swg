#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

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
