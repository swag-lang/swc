#global fileprivate
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
