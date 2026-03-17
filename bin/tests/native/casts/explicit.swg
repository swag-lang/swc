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
