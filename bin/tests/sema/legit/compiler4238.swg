#global fileprivate // swc-option sema-only
#global skip
using Swag

func toto(str: string) {}

#test
{
    toto("titi")
}
