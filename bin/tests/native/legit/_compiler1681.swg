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

alias myStruct = TT

//#[Swag.PrintBc]
func C(x: myStruct)->s64
{
    //@print(cast(s64) x.value)
    @assert(x.value == 456)
    return x.value
}

#test
{
    var x: myStruct
    @assert(C(x) == 456)
}
