#global fileprivate
#global skip
//#[Swag.PrintBc]
func toto1(x: any)
{
    let v = cast(s32) x
    @assert(v == 100)
}

#test
{
    toto1(100)
}
