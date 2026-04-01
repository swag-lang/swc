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
    var a: *A
    a.toto(1)
    A.toto(a, 2)
    a.toto("1") // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: A
    a.toto(1)
    a.titi(10)
    var b: *A
    b.toto(2)
}

#test
{
    var a: A
    a.tata(2)
    A.tata(&a, 3)
    a.tata(1, 2) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    let a = A{}
    a.titi(42)
    a.toto(1) // swc-expected-error {{sema_err_cannot_cast_const}}
    a.tata(2)
}

#test
{
    var p: *A
    A.toto(p, 1, 2) // swc-expected-error {{sema_err_too_many_arguments}}
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
    let opposite = dir.opposite()
    let vertical = dir.isVertical()
    #assert(#typeof(opposite) == Direction)
    #assert(#typeof(vertical) == bool)
}
