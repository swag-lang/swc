#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var pt: Math.Point = 2.0
    @assert(pt.x == 2.0 and pt.y == 2.0)

    pt += Math.Point{1, -3}
    @assert(pt.x == 3.0 and pt.y == -1.0)

    pt *= 2.0
    @assert(pt.x == 6.0 and pt.y == -2.0)

    let neg = -pt
    @assert(neg.x == -6.0 and neg.y == 2.0)

    let shifted = pt + 1.0
    @assert(shifted.x == 7.0 and shifted.y == -1.0)
}

#test
{
    var pt = Math.Point{1.25, -2.75}
    pt.offset(2.0)
    @assert(pt.x == 3.25 and pt.y == -0.75)

    pt.offset(-1.25, 1.75)
    @assert(pt.x == 2.0 and pt.y == 1.0)

    pt.clear()
    @assert(pt.isZero())
    @assert(pt.isZeroEpsilon())
}

#test
{
    var pt = Math.Point{1.25, -1.75}
    pt.round()
    @assert(pt.x == 1.0 and pt.y == -2.0)

    pt = Math.Point{1.75, -1.75}
    pt.trunc()
    @assert(pt.x == 1.0 and pt.y == -1.0)

    pt = Math.Point{1.25, -1.75}
    pt.ceil()
    @assert(pt.x == 2.0 and pt.y == -1.0)

    @assert(Math.Point{1.0, 1.0}.isEqualEpsilon(Math.Point{1.00001, 0.99999}, 0.001))
}
