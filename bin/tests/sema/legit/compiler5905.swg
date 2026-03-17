#global fileprivate // swc-option sema-only
#global skip
struct B {}

impl B
{
    mtd titi() throw
    {
    }

    mtd toto()
    {
        assume .titi()
    }
}
