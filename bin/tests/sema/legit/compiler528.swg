#global fileprivate // swc-option sema-only
#global skip
struct toto {}

impl toto
{
    func f() {}
}

#test
{
    toto.f()
}
