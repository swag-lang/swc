#global fileprivate // swc-option sema-only
#global skip
using Swag

struct(T) A {}

impl A
{
    mtd toto()->A => {}
}

func titi(x: &&A) {}

//#[Swag.PrintBc]
#test
{
    var a: A's32
    titi(a.toto())
}
