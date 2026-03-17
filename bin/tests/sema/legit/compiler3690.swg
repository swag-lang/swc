#global fileprivate // swc-option sema-only
#global skip
struct A {}
impl A
{
    mtd toto()
    {
        mtd titi() {}

        me.titi()
    }
}
