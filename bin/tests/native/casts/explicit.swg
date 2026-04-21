#global fileprivate // 

#test
{
    var u: u8 = 45
    var f = cast(f32) u
    @assert(f == 45.0)
}

#test
{
    var value: f64 = 3.9
    var trunc = cast(s32) value
    @assert(trunc == 3)
}

#test
{
    var raw: u32 = 65
    var ch = cast(rune) raw
    var code = cast(u32) ch

    @assert(ch == 'A')
    @assert(code == raw)
}

#test
{
    var flag: bool = true
    var asByte = cast(u8) flag
    @assert(asByte == 1)
}

func takeStringValue(value: string)->u64
{
    return @countof(value)
}

#test
{
    var text = "seed"
    var textRef: &string = &text
    let textValue = cast(string) textRef

    @assert(textValue == "seed")
    @assert(takeStringValue(textRef) == 4'u64)
}

#test
{
    var text = "seed"
    var textRef: &string = &text
    var snapshot: const &string = cast(string) textRef
    text = "changed"

    @assert(snapshot == "seed")
}
