#global fileprivate
#global skip
struct A {}

struct B
{
    using a: A
}

struct C
{
    using b: B
}

func toto(x: A) {}

#test
{
    var v: C
    toto(v)
}
