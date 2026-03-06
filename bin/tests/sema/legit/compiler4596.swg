#global fileprivate
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
