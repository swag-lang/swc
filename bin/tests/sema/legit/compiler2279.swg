#global fileprivate // swc-option sema-only
#global skip
#global skip
using Swag

struct AA
{
    x: IAllocator
}

func toto(v: const &IAllocator)
{
}

//#[Swag.PrintBc]
#test
{
    var v: AA
    toto(v.x)
}
