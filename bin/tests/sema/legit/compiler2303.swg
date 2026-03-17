#global fileprivate // swc-option sema-only
#global skip
struct AA
{
    xyz: *AA.BB
}

impl AA
{
    const CC = 0

    struct BB {}
}

//#[Swag.PrintBc]
#test
{
    var v: AA
}
