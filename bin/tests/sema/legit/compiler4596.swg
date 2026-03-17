#global fileprivate // swc-option sema-only
#global skip
interface I
{
    mtd toto();
}

struct S {}
impl I for S
{
    mtd impl toto() {}
}
