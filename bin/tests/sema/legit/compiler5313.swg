#global fileprivate // swc-option sema-only
#global skip
namespace C
{
    alias B = s32
}

//#[Swag.PrintBc]
#test
{
    using C
    struct A
    {
        x:   B
    }
}
