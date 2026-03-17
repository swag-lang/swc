#global fileprivate // swc-option sema-only
#global skip
struct A {}

impl A
{
    func toto()
    {
        func titi(me) {}
    }
}
