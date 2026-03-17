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
func C(x: any)->s64
{
    //@print(cast(s64) x.value)
    let val = cast(myStruct) x
    @assert(val.value == 456)
    return val.value
}

#test
{
    var x: myStruct
    @assert(C(x) == 456)
}
