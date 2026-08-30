#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectCurveVec(actual, expected: Math.Vector2)
{
    Swag.assert(actual.isEqualEpsilon(expected, 0.001))
}

func expectCurveRect(actual, expected: Math.Rectangle)
{
    Swag.assert(actual.isEqualEpsilon(expected, 0.001))
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

    expectCurveRect(Math.Curve.bezierBounds(start, end, ctrl), Math.Rectangle{0, 0, 10, 5})
}

#test
{
    let start = Math.Vector2{0, 0}
    let ctrl  = Math.Vector2{5, -10}
    let end   = Math.Vector2{10, 0}

    expectCurveVec(Math.Curve.evaluateBezier(start, end, ctrl, 0.5), Math.Vector2{5, -5})
    expectCurveRect(Math.Curve.bezierBounds(start, end, ctrl), Math.Rectangle{0, -5, 10, 5})
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

    expectCurveRect(Math.Curve.bezierBounds(start, end, ctrl1, ctrl2), Math.Rectangle{0, 0, 10, 7.5})
}

// The closed form of every classic curve, kept here as the reference the preset table is checked
// against. These are the exact expressions the toolkit evaluated before curves became keys, so a
// preset that drifts from its published shape fails this file rather than a screen.
func referencePreset(preset: Math.CurvePreset, p: f32)->f32
{
    const Back      = 1.70158'f32
    const BackInOut = Back * 1.525

    const BounceSteepness = 7.5625'f32
    const BounceSegment   = 1 / 2.75'f32

    switch #complete preset
    {
    case .Linear:
        return p

    case .EaseIn:
        return p * p * p

    case .EaseOut:
        let q = 1 - p
        return 1 - q * q * q

    case .EaseInOut:
        return p * p * (3 - 2 * p)

    case .EaseInBack:
        return p * p * ((Back + 1) * p - Back)

    case .EaseOutBack:
        let q = p - 1
        return 1 + q * q * ((Back + 1) * q + Back)

    case .EaseInOutBack:
        if p < 0.5
        {
            let q = 2 * p
            return q * q * ((BackInOut + 1) * q - BackInOut) * 0.5
        }

        let q = 2 * p - 2
        return (q * q * ((BackInOut + 1) * q + BackInOut) + 2) * 0.5

    case .EaseOutElastic:
        if p <= 0 or p >= 1 do
            return p
        return Math.pow(2'f32, -10 * p) * Math.sin((10 * p - 0.75) * Math.ConstF32.TwoPi / 3) + 1

    case .EaseOutBounce:
        if p < BounceSegment do
            return BounceSteepness * p * p
        if p < 2 * BounceSegment
        {
            let q = p - 1.5 * BounceSegment
            return BounceSteepness * q * q + 0.75
        }

        if p < 2.5 * BounceSegment
        {
            let q = p - 2.25 * BounceSegment
            return BounceSteepness * q * q + 0.9375
        }

        let q = p - 2.625 * BounceSegment
        return BounceSteepness * q * q + 0.984375
    }

    unreachable
}

// Every preset but the spring is piecewise polynomial of degree three or less, so the key form
// reproduces it exactly; the spring is sampled and only has to stay under a thousandth.
func presetTolerance(preset: Math.CurvePreset)->f32
{
    return preset == .EaseOutElastic ? 0.001'f32 : 0.0001'f32
}

// Each preset draws the shape it is named for, all the way along.
#test
{
    const Samples = 256

    for preset in Math.CurvePreset
    {
        var named     = preset
        let tolerance = presetTolerance(preset)
        for step in Samples + 1
        {
            let p = cast(f32) step / cast(f32) Samples
            Swag.assert(Math.isEqualEpsilon(named.evaluate(p), referencePreset(preset, p), tolerance))
        }
    }
}

// Every preset starts on zero, lands on one, and clamps rather than extrapolating outside.
#test
{
    for preset in Math.CurvePreset
    {
        let curve = Math.Curve.shared(preset)
        Swag.assert(Math.isEqualEpsilon(curve.evaluateNormalized(0), 0, 0.0001))
        Swag.assert(Math.isEqualEpsilon(curve.evaluateNormalized(1), 1, 0.0001))
        Swag.assert(curve.evaluateNormalized(-4) == curve.evaluateNormalized(0))
        Swag.assert(curve.evaluateNormalized(9) == curve.evaluateNormalized(1))
    }
}

// The curves chosen for overshoot really leave the unit interval, and the bounce really does not.
#test
{
    var back = Math.CurvePreset.EaseOutBack
    Swag.assert(back.evaluate(0.7) > 1)

    var anticipate = Math.CurvePreset.EaseInBack
    Swag.assert(anticipate.evaluate(0.3) < 0)

    var bounce = Math.CurvePreset.EaseOutBounce
    for step in 101
    {
        let value = bounce.evaluate(cast(f32) step / 100)
        Swag.assert(value >= 0 and value <= 1.0001)
    }
}

// A copy of a preset is an editable curve of its own, and editing it leaves the shared one alone.
#test
{
    var owned = Math.Curve.create(.Linear)
    Swag.assert(owned.keys.count == 2)

    owned.keys[1].y = 4
    Swag.assert(Math.isEqualEpsilon(owned.evaluateNormalized(0.5), 2, 0.0001))
    Swag.assert(Math.isEqualEpsilon(Math.Curve.shared(.Linear).evaluateNormalized(0.5), 0.5, 0.0001))
}

// Keys land in abscissa order however they are added, and the returned index says where.
#test
{
    var curve: Math.Curve
    Swag.assert(curve.isEmpty())
    Swag.assert(curve.evaluateNormalized(0.5) == 0)

    Swag.assert(curve.addKey(1, 1) == 0)
    Swag.assert(curve.addKey(0, 0) == 0)
    Swag.assert(curve.addKey(0.5, 0.25) == 1)
    Swag.assert(curve.keys.count == 3)
    Swag.assert(curve.keys[0].x == 0)
    Swag.assert(curve.keys[1].x == 0.5)
    Swag.assert(curve.keys[2].x == 1)

    // An abscissa edited past its neighbour is what 'sortKeys' exists for.
    curve.keys[0].x = 0.75
    curve.sortKeys()
    Swag.assert(curve.keys[0].x == 0.5)
    Swag.assert(curve.keys[2].x == 1)

    curve.removeKeyAt(1)
    Swag.assert(curve.keys.count == 2)
    Swag.assert(curve.keys[1].x == 1)

    curve.clear()
    Swag.assert(curve.isEmpty())
}

// One curve carries several interpolations at once: a hold, a ramp, then a smooth arrival.
#test
{
    var curve: Math.Curve
    discard curve.addKey(0, 0, .Constant)
    discard curve.addKey(0.25, 0, .Linear)
    discard curve.addKey(0.75, 1, .Smooth)
    discard curve.addKey(1, 2)

    // The constant segment holds its own ordinate right up to the next key.
    Swag.assert(curve.evaluateNormalized(0) == 0)
    Swag.assert(curve.evaluateNormalized(0.2) == 0)

    // The straight segment is read by its chord.
    Swag.assert(Math.isEqualEpsilon(curve.evaluateNormalized(0.5), 0.5, 0.0001))

    // The smoothstep segment is symmetric about its middle and flat at both of its ends, so it
    // leaves the first key behind its own chord and reaches the second one ahead of it.
    Swag.assert(Math.isEqualEpsilon(curve.evaluateNormalized(0.875), 1.5, 0.0001))
    Swag.assert(curve.evaluateNormalized(0.8) < 1.2)
    Swag.assert(curve.evaluateNormalized(0.95) > 1.8)
    Swag.assert(curve.evaluateNormalized(1) == 2)
}

// A key holding two different slopes breaks the curve into a corner instead of rounding it.
#test
{
    var broken: Math.Curve
    discard broken.addKey(0, 0)
    discard broken.addKey(0.5, 1)
    discard broken.addKey(1, 0)
    broken.setTangents(1, 4, -4)

    // The corner is the point both segments reach, and neither flattens onto it.
    Swag.assert(Math.isEqualEpsilon(broken.evaluateNormalized(0.5), 1, 0.0001))
    let rising  = broken.evaluateNormalized(0.5) - broken.evaluateNormalized(0.45)
    let falling = broken.evaluateNormalized(0.55) - broken.evaluateNormalized(0.5)
    Swag.assert(rising > 0.1)
    Swag.assert(falling < -0.1)

    // Smoothing the same key replaces the corner with the chord slope of its neighbours, which is
    // flat here, so the middle key becomes the top of a rounded arch.
    broken.smoothTangents()
    Swag.assert(broken.keys[1].inTangent == broken.keys[1].outTangent)
    Swag.assert(Math.isEqualEpsilon(broken.keys[1].inTangent, 0, 0.0001))
    Swag.assert(broken.evaluateNormalized(0.55) > broken.evaluateNormalized(0.65))
}

// Two keys at one abscissa are a vertical jump: the later one takes over from there on.
#test
{
    var stepped: Math.Curve
    discard stepped.addKey(0, 0, .Constant)
    discard stepped.addKey(0.5, 0, .Constant)
    discard stepped.addKey(0.5, 1, .Constant)
    discard stepped.addKey(1, 1, .Constant)

    Swag.assert(stepped.evaluateNormalized(0.49) == 0)
    Swag.assert(stepped.evaluateNormalized(0.5) == 1)
    Swag.assert(stepped.evaluateNormalized(1) == 1)
}

// A Bézier segment at the neutral weight draws exactly the Hermite segment of the same tangents.
#test
{
    var hermite: Math.Curve
    discard hermite.addKey(0, 0)
    discard hermite.addKey(1, 1)
    hermite.setTangent(0, 2)
    hermite.setTangent(1, 0.5)

    var bezier = hermite
    bezier.keys[0].interpolation = .Bezier

    for step in 65
    {
        let x = cast(f32) step / 64
        Swag.assert(Math.isEqualEpsilon(bezier.evaluateNormalized(x), hermite.evaluateNormalized(x), 0.0005))
    }

    // Lengthening the leaving handle keeps the endpoints and pushes the curve toward its tangent.
    bezier.setWeights(0, Math.Curve.NeutralWeight, 0.9)
    Swag.assert(Math.isEqualEpsilon(bezier.evaluateNormalized(0), 0, 0.0001))
    Swag.assert(Math.isEqualEpsilon(bezier.evaluateNormalized(1), 1, 0.0001))
    Swag.assert(bezier.evaluateNormalized(0.25) > hermite.evaluateNormalized(0.25))
}

// The style-sheet form maps onto the same keys, straight line included.
#test
{
    let straight = Math.Curve.createBezier(1 / 3.0, 1 / 3.0, 2 / 3.0, 2 / 3.0)
    for step in 33
    {
        let x = cast(f32) step / 32
        Swag.assert(Math.isEqualEpsilon(straight.evaluateNormalized(x), x, 0.001))
    }

    // The classic 'ease' of a style sheet starts fast and settles slowly.
    let ease = Math.Curve.createBezier(0.25, 0.1, 0.25, 1)
    Swag.assert(Math.isEqualEpsilon(ease.evaluateNormalized(0), 0, 0.001))
    Swag.assert(Math.isEqualEpsilon(ease.evaluateNormalized(1), 1, 0.001))
    Swag.assert(ease.evaluateNormalized(0.5) > 0.5)

    var previous = 0'f32
    for step in 65
    {
        let value = ease.evaluateNormalized(cast(f32) step / 64)
        Swag.assert(value >= previous - 0.0001)
        previous = value
    }
}

// The user-space window rescales an authored shape without touching its keys.
#test
{
    var curve = Math.Curve.create(.Linear)
    curve.setRange(0, 2, 10, 20)

    Swag.assert(Math.isEqualEpsilon(curve.evaluate(0), 10, 0.0001))
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(1), 15, 0.0001))
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(2), 20, 0.0001))

    // Outside the window the curve still clamps onto its end keys.
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(-5), 10, 0.0001))
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(7), 20, 0.0001))

    // An end below its start mirrors that axis, and the keys are unchanged either way.
    curve.setRange(0, 1, 1, 0)
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(0), 1, 0.0001))
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(0.25), 0.75, 0.0001))
    Swag.assert(Math.isEqualEpsilon(curve.evaluate(1), 0, 0.0001))
    Swag.assert(Math.isEqualEpsilon(curve.evaluateNormalized(0.25), 0.25, 0.0001))

    // An overshooting shape overshoots the window too, which is the point of choosing one.
    var back = Math.Curve.create(.EaseOutBack)
    back.setRange(0, 1, 0, 100)
    Swag.assert(back.evaluate(0.7) > 100)
}

// A curve survives a serialization round trip, keys, tangents, modes and window alike.
#test
{
    var curve: Math.Curve
    discard curve.addKey(0, 0, .Constant)
    discard curve.addKey(0.4, 0.25, .Bezier)
    discard curve.addKey(1, 1)
    curve.setTangents(1, 3, -1)
    curve.setWeights(1, 0.2, 0.8)
    curve.setRange(-1, 3, 5, -5)

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, curve)
    let bytes = buffer.toString()

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let decoded = expect decoder.readAll'Math.Curve(bytes.toSlice())!
    defer Memory.delete(decoded)

    Swag.assert(decoded.keys.count == curve.keys.count)
    Swag.assert(decoded.startX == curve.startX and decoded.endX == curve.endX)
    Swag.assert(decoded.startY == curve.startY and decoded.endY == curve.endY)
    Swag.assert(decoded.keys[0].interpolation == .Constant)
    Swag.assert(decoded.keys[1].interpolation == .Bezier)
    Swag.assert(decoded.keys[1].inTangent == 3 and decoded.keys[1].outTangent == -1)
    Swag.assert(Math.isEqualEpsilon(decoded.keys[1].inWeight, 0.2, 0.0001))
    Swag.assert(Math.isEqualEpsilon(decoded.keys[1].outWeight, 0.8, 0.0001))

    for step in 33
    {
        let x = -1 + cast(f32) step / 8
        Swag.assert(Math.isEqualEpsilon(decoded.evaluate(x), curve.evaluate(x), 0.0001))
    }
}
