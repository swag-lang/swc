// swc-option suite-test

#global fileprivate
#global skip
#global skip
struct TT
{
    value:  s64 = 456
    value1: s64 = 456
    value2: s64 = 456
}

func C(x: const &TT)->s64
{
    @assert(x.value == 456)
    return x.value
}

#test
{
    var x: TT
    @assert(C(x) == 456)
}
