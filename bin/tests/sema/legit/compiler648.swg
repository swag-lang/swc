#global fileprivate // swc-option sema-only
#global skip
var gx: s32

func(T) toto()
{
    let x: T = 100
    gx = x
}

//#[Swag.PrintBc]
//#global testerror
#test
{
    toto's32()
    @assert(gx == 100)
}
