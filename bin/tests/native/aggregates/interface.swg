#global fileprivate // swc-option suite-test

struct A {}

interface I {
    mtd A() -> s32;
}

impl I for A {
    mtd A() -> s32 {
        return 0;
    }
}

namespace B {}


enum ARC { A, B }


interface I0 { mtd toto(); }
struct S0 {}


interface I1 { mtd toto(); }
struct T {}

struct U { t: T }
impl T
{
    mtd toto(x: s32) {}
}

impl I1 for T
{
    mtd impl toto() {}
    func titi() {}
    mtd tata() { me.toto() }
    mtd tonton() { .toto() }
}

#test
{
    T.I1.titi()
}

#test
{
    var a: A
    var i = cast(I) a
    @assert(i.A() == 0)
}

#test
{
    var t: T
    var i = cast(I1) t
    i.toto()
}

