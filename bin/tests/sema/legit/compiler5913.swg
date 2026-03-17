#global fileprivate // swc-option sema-only
#global skip
struct A {}

impl A
{
    mtd tata()
    {
        return
    }

    #[Swag.Mixin]
    mtd titi()
    {
        .tata()
    }
}

#test
{
    var a: A
    a.titi()
}
