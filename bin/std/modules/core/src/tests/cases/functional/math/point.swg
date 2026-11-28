#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.Point.Zero == Math.Point{0, 0})
    Swag.require(Math.Point.One == Math.Point{1, 1})

    var pt: Math.Point = 2.0
    Swag.require(pt == Math.Point{2, 2})

    pt = 0.0
    Swag.require(pt == Math.Point.Zero)

    pt = -3.5
    Swag.require(pt == Math.Point{-3.5, -3.5})

    pt += {1, -3}
    Swag.require(pt == Math.Point{-2.5, -6.5})

    pt -= {-2.5, 0.5}
    Swag.require(pt == Math.Point{0, -7})

    pt *= {4, -5}
    Swag.require(pt == Math.Point{0, 35})

    pt /= {2, -5}
    Swag.require(pt == Math.Point{0, -7})
}

#test
{
    var pt = Math.Point{2, 8}
    pt += 1
    Swag.require(pt == Math.Point{3, 9})

    pt -= 2
    Swag.require(pt == Math.Point{1, 7})

    pt *= 3
    Swag.require(pt == Math.Point{3, 21})

    pt /= 3
    Swag.require(pt == Math.Point{1, 7})

    pt += 0
    Swag.require(pt == Math.Point{1, 7})

    pt *= -2
    Swag.require(pt == Math.Point{-2, -14})

    pt /= -4
    Swag.require(pt == Math.Point{0.5, 3.5})
}

#test
{
    let pt = Math.Point{6, -2}
    Swag.require(pt + {1, 2} == Math.Point{7, 0})
    Swag.require(pt - {1, 2} == Math.Point{5, -4})
    Swag.require(pt * {2, 3} == Math.Point{12, -6})
    Swag.require(pt / {2, -1} == Math.Point{3, 2})

    Swag.require(pt + 1 == Math.Point{7, -1})
    Swag.require(pt - 1 == Math.Point{5, -3})
    Swag.require(pt * 2 == Math.Point{12, -4})
    Swag.require(pt / 2 == Math.Point{3, -1})
    Swag.require(-pt == Math.Point{-6, 2})

    Swag.require(Math.Point.Zero + Math.Point.One == Math.Point.One)
    Swag.require(Math.Point.Zero - Math.Point.One == Math.Point{-1, -1})
    Swag.require(Math.Point{7.5, -3.5} / 2 == Math.Point{3.75, -1.75})

    // Negation flips the sign bit, so the origin negates to (-0, -0): equal to zero as floats,
    // while the member-wise struct comparison compares their bytes.
    let negZero = -Math.Point.Zero
    Swag.require(negZero.x == 0 and negZero.y == 0)
}

#test
{
    var pt = Math.Point{1.25, -2.75}
    pt.offset(0.0)
    Swag.require(pt == Math.Point{1.25, -2.75})

    pt.offset(2.0)
    Swag.require(pt == Math.Point{3.25, -0.75})

    pt.offset(-1.25, 1.75)
    Swag.require(pt == Math.Point{2.0, 1.0})

    Swag.require(not pt.isZero())
    pt.clear()
    Swag.require(pt.isZero())
    Swag.require(pt.isZeroEpsilon())
    Swag.require(not Math.Point{0.01, 0}.isZeroEpsilon(0.001))
    Swag.require(not Math.Point{0, -0.01}.isZeroEpsilon(0.001))
    Swag.require(Math.Point{0.00001, -0.00001}.isZeroEpsilon(0.001))
}

#test
{
    var pt = Math.Point{1.25, -1.75}
    pt.round()
    Swag.require(pt == Math.Point{1, -2})

    pt = {1.75, -1.75}
    pt.trunc()
    Swag.require(pt == Math.Point{1, -1})

    pt = {1.25, -1.75}
    pt.ceil()
    Swag.require(pt == Math.Point{2, -1})

    pt = {-1.25, 1.75}
    pt.round()
    Swag.require(pt == Math.Point{-1, 2})

    pt = {-1.75, 1.75}
    pt.trunc()
    Swag.require(pt == Math.Point{-1, 1})

    pt = {-1.25, 1.25}
    pt.ceil()
    Swag.require(pt == Math.Point{-1, 2})

    Swag.require(Math.Point{1.0, 1.0}.isEqualEpsilon({1.00001, 0.99999}, 0.001))
    Swag.require(not Math.Point{1.0, 1.0}.isEqualEpsilon({1.01, 1.0}, 0.001))
    Swag.require(not Math.Point{1.0, 1.0}.isEqualEpsilon({1.0, 1.01}, 0.001))
}
