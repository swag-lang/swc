#global fileprivate // swc-option sema-only
#global skip
namespace A
{
    struct B {}
}

#test
{
    using A
    func toto(x: B) {}
}
