// 

#global fileprivate
#global skip
//#[Swag.PrintBc]
func toto1(x: any)->s32
{
    let v = cast(s32) x
    @assert(v == 100)
    return v
}

#test
{
    @assert(toto1(100) == 100)
}
