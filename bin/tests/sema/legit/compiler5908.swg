#global fileprivate // swc-option sema-only
#global skip
struct A
{
    x    = 0
}

impl A
{
    func toto(me)
    {
        .x = 1
    }
}
