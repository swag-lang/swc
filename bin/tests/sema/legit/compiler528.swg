#global fileprivate
struct toto {}

impl toto
{
    func f() {}
}

#test
{
    toto.f()
}
