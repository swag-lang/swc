// 

#global fileprivate
 
struct TT
{
    value:      s64 = 456
    value1:     s64 = 456
    value2:     s64 = 456
    value3:     s64 = 456
    value4:     s64 = 456
}

//#[Swag.PrintBc]
func D(x: ...)->s64
{
    return E(x[0])
}

//#[Swag.PrintBc]
func E(x: any)->s64
{
    let ptr = cast(TT) x
    //C(cast(TT) x)
    return C(ptr)
}

//#[Swag.PrintBc]
func C(x: TT)->s64
{
    //@print(cast(s64) x.value)
    @assert(x.value == 456)
    return x.value
}

#test
{
    var x: TT
    @assert(D(x) == 456)
}
