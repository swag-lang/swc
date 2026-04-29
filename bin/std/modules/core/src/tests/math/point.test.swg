#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    @assert(Math.Point.Zero == Math.Point{0, 0})
    @assert(Math.Point.One == Math.Point{1, 1})

    var pt: Math.Point = 2.0
    @assert(pt == Math.Point{2, 2})

    pt += Math.Point{1, -3}
    @assert(pt == Math.Point{3, -1})

    pt -= Math.Point{2, -2}
    @assert(pt == Math.Point{1, 1})

    pt *= Math.Point{4, -5}
    @assert(pt == Math.Point{4, -5})

    pt /= Math.Point{2, -5}
    @assert(pt == Math.Point{2, 1})
}

#test
{
    var pt = Math.Point{2, 8}
    pt += 1
    @assert(pt == Math.Point{3, 9})

    pt -= 2
    @assert(pt == Math.Point{1, 7})

    pt *= 3
    @assert(pt == Math.Point{3, 21})

    pt /= 3
    @assert(pt == Math.Point{1, 7})
}

#test
{
    let pt = Math.Point{6, -2}
    @assert(pt + Math.Point{1, 2} == Math.Point{7, 0})
    @assert(pt - Math.Point{1, 2} == Math.Point{5, -4})
    @assert(pt * Math.Point{2, 3} == Math.Point{12, -6})
    @assert(pt / Math.Point{2, -1} == Math.Point{3, 2})

    @assert(pt + 1 == Math.Point{7, -1})
    @assert(pt - 1 == Math.Point{5, -3})
    @assert(pt * 2 == Math.Point{12, -4})
    @assert(pt / 2 == Math.Point{3, -1})
    @assert(-pt == Math.Point{-6, 2})
}

#test
{
    var pt = Math.Point{1.25, -2.75}
    pt.offset(2.0)
    @assert(pt == Math.Point{3.25, -0.75})

    pt.offset(-1.25, 1.75)
    @assert(pt == Math.Point{2.0, 1.0})

    @assert(!pt.isZero())
    pt.clear()
    @assert(pt.isZero())
    @assert(pt.isZeroEpsilon())
    @assert(!Math.Point{0.01, 0}.isZeroEpsilon(0.001))
}

#test
{
    var pt = Math.Point{1.25, -1.75}
    pt.round()
    @assert(pt == Math.Point{1, -2})

    pt = Math.Point{1.75, -1.75}
    pt.trunc()
    @assert(pt == Math.Point{1, -1})

    pt = Math.Point{1.25, -1.75}
    pt.ceil()
    @assert(pt == Math.Point{2, -1})

    @assert(Math.Point{1.0, 1.0}.isEqualEpsilon(Math.Point{1.00001, 0.99999}, 0.001))
    @assert(!Math.Point{1.0, 1.0}.isEqualEpsilon(Math.Point{1.01, 1.0}, 0.001))
}
