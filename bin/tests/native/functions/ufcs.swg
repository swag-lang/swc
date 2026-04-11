#global fileprivate // 

struct A {}
var gUfcsTotoSum: s32
var gUfcsTitiLast: s32
var gUfcsTataSum: s32

impl A
{
    mtd toto(a: s32) { gUfcsTotoSum += a }
    mtd const titi(a: s32) { gUfcsTitiLast = a }
    func tata(me, a: s32) { gUfcsTataSum += a }

    mtd titi()
    {
        me.toto(3)
        .toto(4)
    }
}

#test
{
    var a: *A
    gUfcsTotoSum = 0
    a.toto(1)
    A.toto(a, 2)
    @assert(gUfcsTotoSum == 3)
}

#test
{
    var a: A
    gUfcsTotoSum = 0
    gUfcsTitiLast = 0
    a.toto(1)
    a.titi(10)
    var b: *A
    b.toto(2)
    @assert(gUfcsTotoSum == 3)
    @assert(gUfcsTitiLast == 10)
}

#test
{
    let a = A{}
    gUfcsTitiLast = 0
    a.titi(42)
    @assert(gUfcsTitiLast == 42)
}

#test
{
    var a: A
    gUfcsTataSum = 0
    a.tata(2)
    A.tata(&a, 3)
    @assert(gUfcsTataSum == 5)
}

enum Direction
{
    North
    East
    South
    West
}

impl Direction
{
    func opposite(me)->Direction
    {
        using Direction
        switch me
        {
        case North: return South
        case South: return North
        case East:  return West
        case West:  return East
        }
    }

    mtd isVertical()->bool
    {
        using Direction
        return me == North or me == South
    }
}

#test
{
    var dir = Direction.North
    @assert(dir.opposite() == Direction.South)
    @assert(dir.isVertical())
    @assert(!Direction.East.isVertical())
}

func invertUfcs(value: bool)->bool => !value

struct UfcsPoint
{
    x, y: s32
}

func setUfcsPoint(pt: *UfcsPoint, value: s32)
{
    pt.x, pt.y = value
}

func addUfcsPoint(pt: *UfcsPoint, dx: s32, dy: s32)
{
    pt.x += dx
    pt.y += dy
}

struct UfcsComplex
{
    real, imag: f32
}

#[Swag.Overload]
func multiplyUfcs(c: *UfcsComplex, scalar: f32)
{
    c.real *= scalar
    c.imag *= scalar
}

#[Swag.Overload]
func multiplyUfcs(c: *UfcsComplex, other: *UfcsComplex)
{
    let r = (c.real * other.real) - (c.imag * other.imag)
    let i = (c.real * other.imag) + (c.imag * other.real)
    c.real = r
    c.imag = i
}

#test
{
    let value = false
    @assert(invertUfcs(value) == value.invertUfcs())
}

#test
{
    var pt: UfcsPoint
    pt.setUfcsPoint(10)
    @assert(pt.x == 10 and pt.y == 10)

    addUfcsPoint(&pt, 3, 4)
    @assert(pt.x == 13 and pt.y == 14)

    pt.addUfcsPoint(1, 2)
    @assert(pt.x == 14 and pt.y == 16)
}

#test
{
    var c1 = UfcsComplex{2.0, 3.0}
    var c2 = UfcsComplex{4.0, 5.0}

    c1.multiplyUfcs(2.0)
    @assert(c1.real == 4.0 and c1.imag == 6.0)

    c1.multiplyUfcs(&c2)
    @assert(c1.real == -14.0 and c1.imag == 44.0)
}

