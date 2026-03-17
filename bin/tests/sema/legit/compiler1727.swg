#global fileprivate // swc-option sema-only
#global skip
#test
{
    struct A
    {
        name: string = "toto"
    }

    struct B
    {
        using root: A
    }

    func F(ptr: *B) {}

    var v: B
    F(&v)
}
