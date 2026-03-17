#global fileprivate // swc-option sema-only
#global skip
struct A
{
    x    = 0
}

impl A
{
    #[Swag.Macro]
    mtd titi()
    {
        if !.x do
            return
    }
}

#test
{
    var a: A
    a.titi()
}
