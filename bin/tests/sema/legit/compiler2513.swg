#global fileprivate
#global skip
func toto(x: string)->[100] u8
{
    var result: retval
    let len     = @countof(x)
    @memcpy(@dataof(result), @dataof(x), len)
    result[len] = 0
    return result
}

//#[Swag.PrintBc]
#test
{
    let x = toto("toto")
    @assert(@countof(cast(cstring) @dataof(x)) == 4)
}
