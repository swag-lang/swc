#global fileprivate // swc-option sema-only
#global skip
using Swag

struct TOTO
{
    x:   func(*TOTO)
}

//#[Swag.PrintBc]
#test
{
    var ptr = cast(const *TypeInfoStruct) #typeof(TOTO)
}
