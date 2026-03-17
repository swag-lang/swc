#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    @assert(toto(4) == 16)
}

func toto(x: s32) => x * x
