#global fileprivate

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

// Interface declarations require 'mtd'.
interface IReset
{
    mtd set(val: f32);
    mtd reset();
}

struct Point2 { x, y: f32 }
struct Point3 { x, y, z: f32 }

impl IReset for Point2
{
    mtd impl set(val: f32)
    {
        me.x = val
        me.y = val + 1
    }

    mtd impl reset()
    {
        me.x, me.y = 0
    }
}

impl IReset for Point3
{
    mtd impl set(val: f32)
    {
        me.x = val
        me.y = val + 1
        me.z = val + 2
    }

    mtd impl reset()
    {
        me.x, me.y, me.z = 0
    }
}

// Cast to interface and call methods on multiple structs.
/* @BUG
#test
{
    var pt2: Point2
    var pt3: Point3

    var itf = cast(IReset) pt2
    itf.set(10)
    @assert(pt2.x == 10)
    @assert(pt2.y == 11)

    itf = cast(IReset) pt3
    itf.set(10)
    @assert(pt3.x == 10)
    @assert(pt3.y == 11)
    @assert(pt3.z == 12)
    itf.reset()
    @assert(pt3.x == 0 and pt3.y == 0 and pt3.z == 0)
}*/

// Direct interface method access on instances.
/* @BUG
#test
{
    var pt2: Point2
    var pt3: Point3

    pt2.IReset.set(10)
    @assert(pt2.x == 10 and pt2.y == 11)
    pt2.IReset.reset()
    @assert(pt2.x == 0 and pt2.y == 0)

    pt3.IReset.set(10)
    @assert(pt3.x == 10 and pt3.y == 11 and pt3.z == 12)
    pt3.IReset.reset()
    @assert(pt3.x == 0 and pt3.y == 0 and pt3.z == 0)
}*/

// Interface size, @kindof, @dataof.
#test
{
    var pt2: Point2
    var pt3: Point3
    var itf = cast(IReset) pt2

    #assert(#sizeof(itf) == 2 * #sizeof(*void))

    itf = cast(IReset) pt2
    @assert(@kindof(itf) == Point2)
    itf = cast(IReset) pt3
    @assert(@kindof(itf) == Point3)

    itf = cast(IReset) pt2
    @assert(@dataof(itf) == &pt2)
    itf = cast(IReset) pt3
    @assert(@dataof(itf) == &pt3)
}
