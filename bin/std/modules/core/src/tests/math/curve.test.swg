#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func expectVec2(actual, expected: Math.Vector2)
{
    @assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectRect(actual, expected: Math.Rectangle)
{
    @assert(actual.isEqualEpsilon(expected, 0.001))
}

#test
{
    let p0 = Math.Vector2{1, 2}
    let p1 = Math.Vector2{3, -4}
    let p2 = Math.Vector2{-2, 5}
    let p3 = Math.Vector2{7, 11}

    expectVec2(Math.Curve.evaluatePolynomial(p0, p1, p2, p3, 0), p3)
    expectVec2(Math.Curve.evaluatePolynomial(p0, p1, p2, p3, 1), Math.Vector2{9, 14})
    expectVec2(Math.Curve.evaluatePolynomial(p0, p1, p2, p3, 2), Math.Vector2{27, 23})
}

#test
{
    let start = Math.Vector2{0, 0}
    let end   = Math.Vector2{10, 0}
    let ctrl  = Math.Vector2{0, 10}

    expectVec2(Math.Curve.evaluateBezier(start, end, ctrl, 0), start)
    expectVec2(Math.Curve.evaluateBezier(start, end, ctrl, 1), end)
    expectVec2(Math.Curve.evaluateBezier(start, end, ctrl, 0.5), Math.Vector2{2.5, 5})
}

#test
{
    let start = Math.Vector2{0, 0}
    let end   = Math.Vector2{10, 0}
    let ctrl0 = Math.Vector2{0, 12}
    let ctrl1 = Math.Vector2{10, 12}

    expectVec2(Math.Curve.evaluateBezier(start, end, ctrl0, ctrl1, 0), start)
    expectVec2(Math.Curve.evaluateBezier(start, end, ctrl0, ctrl1, 1), end)
    expectVec2(Math.Curve.evaluateBezier(start, end, ctrl0, ctrl1, 0.5), Math.Vector2{5, 9})
}

#test
{
    expectRect(
        Math.Curve.getBezierBoundingBox(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{5, 10}),
        Math.Rectangle{0, 0, 10, 5})

    expectRect(
        Math.Curve.getBezierBoundingBox(Math.Vector2{0, 0}, Math.Vector2{10, 0}, Math.Vector2{0, 12}, Math.Vector2{10, 12}),
        Math.Rectangle{0, 0, 10, 9})
}
