#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectCurveVec(actual, expected: Math.Vector2)
{
    @assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectCurveRect(actual, expected: Math.Rectangle)
{
    @assert(actual.isEqualEpsilon(expected, 0.001))
}

#test
{
    let p0 = Math.Vector2{1, 2}
    let p1 = Math.Vector2{-3, 4}
    let p2 = Math.Vector2{5, -6}
    let p3 = Math.Vector2{7, 8}

    expectCurveVec(Math.Curve.evaluatePolynomial(p0, p1, p2, p3, 0), p3)
    expectCurveVec(Math.Curve.evaluatePolynomial(p0, p1, p2, p3, 1), Math.Vector2{10, 8})
    expectCurveVec(Math.Curve.evaluatePolynomial(p0, p1, p2, p3, 2), Math.Vector2{13, 28})
}

#test
{
    let start = Math.Vector2{0, 0}
    let ctrl  = Math.Vector2{10, 10}
    let end   = Math.Vector2{10, 0}

    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl, 0), start)
    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl, 0.5), Math.Vector2{7.5, 5})
    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl, 1), end)

    expectCurveRect(Math.Curve.getBezierBoundingBox(start, end, ctrl), Math.Rectangle{0, 0, 10, 5})
}

#test
{
    let start = Math.Vector2{0, 0}
    let ctrl  = Math.Vector2{5, -10}
    let end   = Math.Vector2{10, 0}

    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl, 0.5), Math.Vector2{5, -5})
    expectCurveRect(Math.Curve.getBezierBoundingBox(start, end, ctrl), Math.Rectangle{0, -5, 10, 5})
}

#test
{
    let start = Math.Vector2{0, 0}
    let ctrl1 = Math.Vector2{0, 10}
    let ctrl2 = Math.Vector2{10, 10}
    let end   = Math.Vector2{10, 0}

    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl1, ctrl2, 0), start)
    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl1, ctrl2, 0.5), Math.Vector2{5, 7.5})
    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl1, ctrl2, 1), end)

    expectCurveRect(Math.Curve.getBezierBoundingBox(start, end, ctrl1, ctrl2), Math.Rectangle{0, 0, 10, 7.5})
}
