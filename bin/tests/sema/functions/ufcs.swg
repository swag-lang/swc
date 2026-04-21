#global fileprivate

struct A {}

impl A
{
    mtd toto(a: s32) {}
    mtd const titi(a: s32) {}
    func tata(me, a: s32) {}

    mtd titi()
    {
        me.toto(3)
        .toto(4)
    }
}

#test
{
    var a: A
    a.toto(1)
    a.titi(10)
    var b: *A
    b.toto(2)
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
    let opposite = dir.opposite()
    let vertical = dir.isVertical()
    #assert(#typeof(opposite) == Direction)
    #assert(#typeof(vertical) == bool)
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
    #assert(#typeof(value.invertUfcs()) == bool)
}

#test
{
    var pt: UfcsPoint
    pt.setUfcsPoint(10)
    pt.addUfcsPoint(1, 2)
}

#test
{
    var c1 = UfcsComplex{2.0, 3.0}
    var c2 = UfcsComplex{4.0, 5.0}
    c1.multiplyUfcs(2.0)
    c1.multiplyUfcs(&c2)
}
