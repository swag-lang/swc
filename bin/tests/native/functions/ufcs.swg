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

impl enum Direction
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

