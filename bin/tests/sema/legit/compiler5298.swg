#global fileprivate
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
