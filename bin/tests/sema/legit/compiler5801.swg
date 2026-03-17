#global fileprivate // swc-option sema-only
#global skip
interface I
{
    mtd toto();
}

impl I for B
{
    mtd impl toto()
    {
        @print("toto")
    }
}

impl I for A
{
}

struct B {}

struct A
{
    using b: B
}

func titi()
{
    var a: A
    a.I.toto()
}
