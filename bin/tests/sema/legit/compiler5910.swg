#global fileprivate // swc-option sema-only
#global skip
struct A {}

impl A
{
    mtd titi()->s32
    {
        return 0
    }

    mtd toto()
    {
        discard .titi()
    }
}
