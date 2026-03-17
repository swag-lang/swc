#global fileprivate // swc-option sema-only
#global skip
struct A {}

impl A
{
    mtd titi()
    {
        return
    }

    mtd toto()
    {
        let f = mtd||()
        {
            .titi()
        }
    }
}
