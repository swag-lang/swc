#global fileprivate // swc-option sema-only
#global skip
struct A {}

impl A
{
    mtd tata()
    {
        return
    }

    mtd toto()
    {
        #[Swag.Mixin]
        func titi()
        {
            .tata()
        }
    }
}
