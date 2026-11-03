#global private

#test
{
    var u: u8 = 45
    var f     = cast(f32, u)
    Swag.require(f == 45.0)
}

#test
{
    var value: f64 = 3.9
    var trunc      = cast(s32, value)
    Swag.require(trunc == 3)
}

#test
{
    var raw: u32 = 65
    var ch       = cast(rune, raw)
    var code     = cast(u32, ch)

    Swag.require(ch == 'A')
    Swag.require(code == raw)
}

#test
{
    var flag: bool = true
    var asByte     = cast(u8, flag)
    Swag.require(asByte == 1)
}

func takeStringValue(value: string)->u64
{
    return value.count
}

#test
{
    var text             = "seed"
    var textRef: *string = &text
    let textValue        = cast(string, textRef[])

    Swag.require(textValue == "seed")
    Swag.require(takeStringValue(textRef[]) == 4'u64)
}

#test
{
    var text             = "seed"
    var textRef: *string = &text
    let snapshot         = cast(string, textRef[])
    text = "changed"

    Swag.require(snapshot == "seed")
}
