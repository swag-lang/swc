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
var gInterfaceTitiCalls: s32
var gInterfaceImplTotoCalls: s32
impl T
{
    mtd toto(x: s32) {}
}

impl I1 for T
{
    mtd impl toto() { gInterfaceImplTotoCalls += 1 }
    func titi() { gInterfaceTitiCalls += 1 }
    mtd tata() { me.toto() }
    mtd tonton() { .toto() }
}

#test
{
    gInterfaceTitiCalls = 0
    T.I1.titi()
    @assert(gInterfaceTitiCalls == 1)
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
    gInterfaceImplTotoCalls = 0
    i.toto()
    @assert(gInterfaceImplTotoCalls == 1)
}

