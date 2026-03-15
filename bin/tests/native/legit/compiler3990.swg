// swc-option suite-test

#global fileprivate
#global skip
struct TT
{
    value:      s64 = 456
    value1:     s64 = 456
    value2:     s64 = 456
}

func D(x: const &TT)->s64
{
    //@print(cast(s64) x.value)
    @assert(x.value == 456)
    return x.value
}

//#[Swag.PrintBc]
func C(x: any)->s64
{
    return D(x)
}

#test
{
    var x: TT
    @assert(C(x) == 456)
}
