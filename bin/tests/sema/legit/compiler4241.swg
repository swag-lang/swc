#global fileprivate // swc-option sema-only
#global skip
using Swag

func toto(a: s32, str: string) {}

#test
{
    toto(0, "titi")
}
