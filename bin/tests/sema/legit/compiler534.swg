// @FAIL
#global skip
#global fileprivate
func toto(x: s32)
{
    @assert(x == 666)
}

//#[Swag.PrintBc]
#test
{
    let a = 666
    a.toto()
}
