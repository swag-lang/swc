#global namespace Math
#global public

// Selects how the segment leaving one key reaches the next one.
//
// The mode belongs to the key the segment starts at, so a single curve can hold a stepped hold, a
// straight ramp and a smooth ease at once.
enum CurveInterpolation
{
    Constant     // Holds the ordinate of the starting key until the next key.
    Linear       // Straight line between the two keys; ignores both tangents.
    Smooth       // Smoothstep between the two keys; ignores both tangents.
    Hermite      // Cubic leaving and entering along the tangents, with neutral handle lengths.
    Bezier       // Cubic Bézier along the tangents, over the handle lengths the weights ask for.
}

// One control point of a [[Core.Math.Curve]].
//
// A key carries an arriving and a leaving tangent. Giving them the same value makes the curve
// smooth across the key; giving them different values breaks it into a corner, which is how a
// bounce lands and rebounds. Both are slopes, in ordinate units per abscissa unit, so they keep
// their meaning when a neighbouring key moves.
struct CurveKey
{
    public
    {
        x:             f32                               // Abscissa of the key, normally inside the unit interval.
        y:             f32                               // Ordinate of the key, free to leave the unit interval.
        inTangent:     f32                               // Slope of the segment arriving at the key.
        outTangent:    f32                               // Slope of the segment leaving the key.
        inWeight:      f32                = 1 / 3.0      // Length of the arriving Bézier handle, as a fraction of the segment width.
        outWeight:     f32                = 1 / 3.0      // Length of the leaving Bézier handle, as a fraction of the segment width.
        interpolation: CurveInterpolation = .Hermite     // Interpolation of the segment leaving this key.
    }
}

// Names one classic curve, the shape a caller asks for instead of authoring it.
//
// The last five leave the unit interval on purpose: an anticipating or overshooting shape passes
// beyond its endpoints before settling on them.
enum CurvePreset
{
    Linear             // Keeps the ordinate proportional to the abscissa.
    EaseIn             // Accelerates from rest.
    EaseOut            // Decelerates toward rest.
    EaseInOut          // Accelerates, then decelerates symmetrically.
    EaseInBack         // Draws back below zero, then accelerates.
    EaseOutBack        // Overshoots one, then settles onto it.
    EaseInOutBack      // Draws back, accelerates, overshoots, then settles.
    EaseOutElastic     // Springs past one and oscillates onto it.
    EaseOutBounce      // Lands on one and rebounds with decreasing height.
}

impl CurvePreset
{
    // Returns the ordinate of this classic shape at `x`, clamped to the unit interval.
    //
    // This reads the shared curve of the preset and allocates nothing, so plotting a preview and
    // running an animation go through one evaluator and cannot drift apart.
    //
    // The method reads the preset and changes nothing. It is not declared `const` because a
    // `const` receiver over an enum currently compiles at neither end; see `F-090`. It names every
    // symbol it uses in full because a method declared over an enum is published to other modules
    // with its source rather than as an import; see `F-091`.
    mtd evaluate(x: f32)->f32
    {
        return Math.Curve.shared(me).evaluateNormalized(x)
    }
}

// A curve of arbitrarily many keys, evaluated as one ordinate for one abscissa.
//
// A curve is authored inside the unit square, and [[Core.Math.Curve.evaluateNormalized]] answers in
// that space. `startX`, `endX`, `startY` and `endY` map that square onto whatever range a caller
// works in, so one authored shape drives seconds, pixels or degrees through
// [[Core.Math.Curve.evaluate]] without being re-authored.
//
// Every key owns its two tangents and the interpolation of the segment leaving it, so one curve
// expresses a smooth ease, a stepped hold and a corner at once — any shape, broken or not. The
// type is a plain aggregate over a [[Core.Array]]: it copies, serializes and drops like any other
// value.
struct Curve
{
    public
    {
        // Keys of the curve, kept sorted by ascending abscissa.
        //
        // [[Core.Math.Curve.addKey]] maintains that order. Editing a key in place is allowed, and is how a
        // curve editor retimes one; call [[Core.Math.Curve.sortKeys]] afterwards when the edit moved a key
        // past a neighbour.
        keys: Array'CurveKey

        // User-space window the normalized unit square maps onto.
        //
        // [[Core.Math.Curve.evaluate]] reads an abscissa between `startX` and `endX` and answers an
        // ordinate between `startY` and `endY`. The defaults leave both axes normalized, and an end
        // below its start mirrors that axis.
        startX: f32
        endX:   f32 = 1
        startY: f32
        endY:   f32 = 1
    }
}

private impl Curve
{
    // Anticipation of the classic back curves. It makes `EaseOutBack` peak about ten percent past
    // its end value, which reads as weight rather than as a mistake; the symmetric form widens it
    // so both halves keep that proportion.
    const BackOvershoot          = 1.70158'f32
    const BackOvershootSymmetric = BackOvershoot * 1.525

    // Builds one key, tangents included.
    func makeKey(x, y, inTangent, outTangent: f32, interpolation = CurveInterpolation.Hermite)->CurveKey
    {
        var result: retval
        result.x             = x
        result.y             = y
        result.inTangent     = inTangent
        result.outTangent    = outTangent
        result.interpolation = interpolation
        return result
    }

    func makeLinear()->Curve
    {
        var result: retval
        result.keys.add(makeKey(0, 0, 0, 0, .Linear))
        result.keys.add(makeKey(1, 1, 0, 0, .Linear))
        return result
    }

    // Builds the rise from zero to one drawn by a single Hermite segment leaving the origin at
    // `outTangent` and reaching one at `inTangent`.
    //
    // Every classic curve that is not piecewise is exactly one such segment: a cubic is fully
    // determined by the values and the slopes at its two ends, so `EaseIn`, `EaseOut`,
    // `EaseInOut` and the two single-sided back curves are reproduced to the last bit here rather
    // than approximated.
    func makeEase(outTangent, inTangent: f32)->Curve
    {
        var result: retval
        result.keys.add(makeKey(0, 0, 0, outTangent))
        result.keys.add(makeKey(1, 1, inTangent, 0))
        return result
    }

    // Builds the symmetric back curve, whose two halves meet at the middle of the unit square.
    func makeSymmetricBack()->Curve
    {
        let middle = BackOvershootSymmetric + 3

        var result: retval
        result.keys.add(makeKey(0, 0, 0, 0))
        result.keys.add(makeKey(0.5, 0.5, middle, middle))
        result.keys.add(makeKey(1, 1, 0, 0))
        return result
    }

    // Builds the classic bounce: four parabolas of decreasing height, landing on one each time.
    //
    // Each parabola is exact as a Hermite segment, because the cubic through the values and the
    // slopes of a quadratic is that quadratic. This curve is the reason a key carries two
    // tangents: every landing arrives climbing and leaves falling.
    func makeBounce()->Curve
    {
        const Steepness = 7.5625'f32
        const Segment   = 1 / 2.75'f32

        // Slope at which the second parabola leaves the first landing. Every later rebound leaves
        // at half the previous one, which is what makes the bounce die out.
        const Rebound = Steepness * Segment

        var result: retval
        result.keys.add(makeKey(0, 0, 0, 0))
        result.keys.add(makeKey(Segment, 1, 2 * Rebound, -Rebound))
        result.keys.add(makeKey(2 * Segment, 1, Rebound, -0.5 * Rebound))
        result.keys.add(makeKey(2.5 * Segment, 1, 0.5 * Rebound, -0.25 * Rebound))
        result.keys.add(makeKey(1, 1, 0.25 * Rebound, 0))
        return result
    }

    // Builds the elastic spring: a sine of decaying amplitude settling onto one.
    //
    // A decaying sine has no exact piecewise-cubic form, so it is sampled where its value and its
    // slope are both known in closed form — every eighth of a period, where the sine and the
    // cosine are exactly zero, one, or half a square root of two. A Hermite segment between two
    // such samples stays within a thousandth of the closed form, far below what a screen resolves;
    // sampling every quarter period instead costs sixteen times that, which is enough to see.
    func makeElastic()->Curve
    {
        const Decay  = 10'f32                              // Amplitude falls as two to the minus 'Decay' times the abscissa.
        const Omega  = Decay * Math.ConstF32.TwoPi / 3     // Angular speed of the sine, in radians per abscissa unit.
        const Eighth = 0.0375'f32                          // Abscissa covered by one eighth of a period.
        const Steps  = 27                                  // Eighths of a period that fit inside the unit interval.

        // Sine and cosine of a sample, indexed by the eighth it sits on. The spring starts at the
        // trough, which is what puts its first sample exactly on zero.
        const Diagonal = Math.ConstF32.OneBySqrt2
        const Sines    = [0'f32, Diagonal, 1, Diagonal, 0, -Diagonal, -1, -Diagonal]
        const Cosines  = [1'f32, Diagonal, 0, -Diagonal, -1, -Diagonal, 0, Diagonal]

        var result: retval
        for index in Steps
        {
            let eighth   = (index + 6) % 8
            let x        = cast(f32) index * Eighth
            let envelope = Math.pow(2'f32, -Decay * x)
            let value    = envelope * Sines[eighth] + 1
            let slope    = envelope * (Omega * Cosines[eighth] - Decay * Math.ConstF32.Ln2 * Sines[eighth])
            result.keys.add(makeKey(x, value, slope, slope))
        }

        // The last sample sits an eighth of a period short of the end and the spring is settled by
        // then, so the curve simply lands flat on one.
        result.keys.add(makeKey(1, 1, 0, 0))
        return result
    }

    // Returns the ordinate at `x` of the segment leaving `k0` and reaching `k1`.
    func segmentValue(k0, k1: CurveKey, x: f32)->f32
    {
        let span = k1.x - k0.x
        if span <= 0 do
            return k1.y

        let t = (x - k0.x) / span
        switch #complete k0.interpolation
        {
        case .Constant: return k0.y
        case .Linear:   return Math.lerp(k0.y, k1.y, t)
        case .Smooth:   return Math.lerp(k0.y, k1.y, t * t * (3 - 2 * t))
        case .Hermite:  return hermiteValue(k0.y, k1.y, k0.outTangent * span, k1.inTangent * span, t)
        case .Bezier:   return bezierValue(k0, k1, span, t)
        }

        unreachable
    }

    // Returns the cubic Hermite value, with both tangents already scaled by the segment width.
    func hermiteValue(y0, y1, m0, m1, t: f32)->f32
    {
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0 + (3 * t2 - 2 * t3) * y1 + (t3 - t2) * m1
    }

    // Returns the ordinate of a weighted Bézier segment at the abscissa fraction `t`.
    //
    // The handles lie along the tangents, over the lengths the weights ask for. A weight moves the
    // abscissa of its handle, so the parameter of the curve stops following the abscissa and has
    // to be solved for before the ordinate can be read.
    func bezierValue(k0, k1: CurveKey, span, t: f32)->f32
    {
        // A handle reaching past the far key would fold the segment back over itself, and one
        // abscissa would stop naming one ordinate.
        let outWeight = Math.saturate(k0.outWeight)
        let inWeight  = Math.saturate(k1.inWeight)

        let param = solveBezierParam(outWeight, 1 - inWeight, t)
        let low   = k0.y + span * outWeight * k0.outTangent
        let high  = k1.y - span * inWeight * k1.inTangent
        let rest  = 1 - param
        return rest * rest * rest * k0.y + 3 * rest * rest * param * low + 3 * rest * param * param * high + param * param * param * k1.y
    }

    // Returns the parameter at which a unit Bézier of abscissa controls `c1` and `c2` reaches the
    // abscissa `x`.
    //
    // Newton closes in a few steps on the shapes a curve editor produces. The bisection below is
    // what answers when the abscissa derivative collapses, which happens as soon as a handle
    // reaches the end of its segment.
    func solveBezierParam(c1, c2, x: f32)->f32
    {
        const NewtonSteps    = 8
        const BisectionSteps = 24
        const FlatDerivative = 1e-5'f32
        const Precision      = 1e-6'f32

        var param = x
        for NewtonSteps
        {
            let error = bezierAbscissa(c1, c2, param) - x
            if Math.abs(error) < Precision do
                return param

            let slope = bezierAbscissaSlope(c1, c2, param)
            if Math.abs(slope) < FlatDerivative do
                break
            param -= error / slope
        }

        var low  = 0'f32
        var high = 1'f32
        param = Math.saturate(x)
        for BisectionSteps
        {
            let error = bezierAbscissa(c1, c2, param) - x
            if Math.abs(error) < Precision do
                return param
            if error > 0 do
                high = param
            else do
                low = param
            param = (low + high) * 0.5
        }

        return param
    }

    // Returns the abscissa of a unit Bézier whose interior controls sit at `c1` and `c2`.
    func bezierAbscissa(c1, c2, t: f32)->f32
    {
        let rest = 1 - t
        return 3 * rest * rest * t * c1 + 3 * rest * t * t * c2 + t * t * t
    }

    // Returns the derivative of the abscissa of that unit Bézier, against its parameter.
    func bezierAbscissaSlope(c1, c2, t: f32)->f32
    {
        let rest = 1 - t
        return 3 * rest * rest * c1 + 6 * rest * t * (c2 - c1) + 3 * t * t * (1 - c2)
    }
}

impl Curve
{
    // Handle length at which a `Bezier` segment draws exactly the `Hermite` segment of the same
    // tangents. It is the default of both weights, so a weight is only felt once it is changed.
    const NeutralWeight = 1 / 3.0'f32

    // Returns the classic curve named by `preset`, owned by the caller and free to edit.
    //
    // Use [[Core.Math.Curve.shared]] instead when the curve is only going to be read.
    func create(preset: CurvePreset)->Curve
    {
        switch #complete preset
        {
        case .Linear:         return makeLinear()
        case .EaseIn:         return makeEase(0, 3)
        case .EaseOut:        return makeEase(3, 0)
        case .EaseInOut:      return makeEase(0, 0)
        case .EaseInBack:     return makeEase(0, BackOvershoot + 3)
        case .EaseOutBack:    return makeEase(BackOvershoot + 3, 0)
        case .EaseInOutBack:  return makeSymmetricBack()
        case .EaseOutElastic: return makeElastic()
        case .EaseOutBounce:  return makeBounce()
        }

        unreachable
    }

    // Returns the process-wide instance of a classic curve, borrowed rather than owned.
    //
    // The table is built once, before any application code runs, and never changes afterwards, so
    // an evaluator that only reads a preset neither owns a curve nor rebuilds one.
    func shared(preset: CurvePreset)->const &Curve => &g_CurvePresets[preset]

    // Returns the curve of the `cubic-bezier(x1, y1, x2, y2)` form used by style sheets.
    //
    // The two handles are given as positions in the unit square, the way the CSS function spells
    // them. Both abscissas are clamped to that interval, because a handle leaving it makes the
    // curve stop being a function of its abscissa; the ordinates are free, which is what lets the
    // form overshoot.
    func createBezier(x1, y1, x2, y2: f32)->Curve
    {
        let outWeight = Math.saturate(x1)
        let inWeight  = 1 - Math.saturate(x2)
        let outSlope  = outWeight > 0 ? y1 / outWeight : 0'f32
        let inSlope   = inWeight > 0 ? (1 - y2) / inWeight : 0'f32

        var result: retval
        var first  = makeKey(0, 0, 0, outSlope, .Bezier)
        var second = makeKey(1, 1, inSlope, 0, .Bezier)
        first.outWeight = outWeight
        second.inWeight = inWeight
        result.keys.add(first)
        result.keys.add(second)
        return result
    }

    // Removes every key, leaving the user-space window untouched.
    mtd clear()
    {
        .keys.clear()
    }

    // Reports whether the curve holds no key at all.
    mtd const isEmpty() => .keys.isEmpty()

    // Inserts `key` at its place in abscissa order and returns the index it landed on.
    //
    // A key sharing the abscissa of an existing one is inserted after it. That is how a vertical
    // jump is authored: the segment between the two is empty, so the later key takes over from
    // that abscissa on.
    mtd addKey(key: CurveKey)->u64
    {
        var index = .keys.count
        while index and .keys[index - 1].x > key.x do
            index -= 1
        .keys.insertAt(index, key)
        return index
    }

    // Inserts a key with no tangent at `x`, `y` and returns the index it landed on.
    mtd addKey(x, y: f32, interpolation = CurveInterpolation.Hermite)->u64
    {
        return .addKey(makeKey(x, y, 0, 0, interpolation))
    }

    // Removes the key at `index`, keeping the remaining ones in order.
    mtd removeKeyAt(index: u64)
    {
        .keys.removeAtOrdered(index)
    }

    // Restores the abscissa order after keys were edited in place.
    mtd sortKeys()
    {
        .keys.sort(func||(left, right) { return left.x <=> right.x })
    }

    // Gives the key at `index` one slope on both sides, making the curve smooth across it.
    mtd setTangent(index: u64, tangent: f32)
    {
        .setTangents(index, tangent, tangent)
    }

    // Gives the key at `index` two different slopes, breaking the curve into a corner.
    mtd setTangents(index: u64, inTangent, outTangent: f32)
    {
        .keys[index].inTangent  = inTangent
        .keys[index].outTangent = outTangent
    }

    // Sets the Bézier handle lengths of the key at `index`, as fractions of their segment.
    //
    // They are only read by a `Bezier` segment, and [[Core.Math.Curve.NeutralWeight]] is the length at
    // which one draws its `Hermite` equivalent.
    mtd setWeights(index: u64, inWeight, outWeight: f32)
    {
        .keys[index].inWeight  = inWeight
        .keys[index].outWeight = outWeight
    }

    // Recomputes every tangent from the neighbours of its key, leaving no corner behind.
    //
    // Each interior key takes the slope of the chord between the keys on either side, and each end
    // takes the slope of its own segment. That is the curve a caller expects after dropping a
    // handful of points with no tangent in mind.
    mtd smoothTangents()
    {
        let count = .keys.count
        if count < 2 do
            return

        for index in count
        {
            let low  = index ? index - 1 : index
            let high = index + 1 < count ? index + 1 : index
            let span = .keys[high].x - .keys[low].x
            .setTangent(index, span > 0 ? (.keys[high].y - .keys[low].y) / span : 0'f32)
        }
    }

    // Maps the normalized unit square onto a user-space window.
    //
    // An end below its start mirrors that axis, which is how a curve authored rising is reused to
    // drive a value that falls.
    mtd setRange(startX, endX, startY, endY: f32)
    {
        .startX = startX
        .endX   = endX
        .startY = startY
        .endY   = endY
    }

    // Returns the ordinate at `x` in the authored unit square.
    //
    // An abscissa outside the keys is clamped onto the nearest one, so a curve never extrapolates
    // a shape it was not given. A curve with no key answers zero.
    mtd const evaluateNormalized(x: f32)->f32
    {
        let count = .keys.count
        if !count do
            return 0'f32

        let first = .keys[0]
        if x <= first.x do
            return first.y

        let last = .keys[count - 1]
        if x >= last.x do
            return last.y

        // The abscissa now sits strictly inside the keys, so this search always closes on one
        // segment: 'low' stays at or before it, and 'high' stays after it.
        var low  = 0'u64
        var high = count - 1
        while high - low > 1
        {
            let mid = (low + high) >> 1
            if .keys[mid].x <= x do
                low = mid
            else do
                high = mid
        }

        let k0 = .keys[low]
        let k1 = .keys[high]
        return segmentValue(k0, k1, x)
    }

    // Returns the user-space ordinate at the user-space abscissa `x`.
    //
    // This is [[Core.Math.Curve.evaluateNormalized]] read through the window
    // [[Core.Math.Curve.setRange]] installed. A window with no width answers the first key, because
    // every abscissa then names the same normalized position.
    mtd const evaluate(x: f32)->f32
    {
        let span       = .endX - .startX
        let normalized = span != 0 ? (x - .startX) / span : 0'f32
        return Math.lerp(.startY, .endY, .evaluateNormalized(normalized))
    }

    // Evaluate a cubic polynomial at parameter 't'.
    // Uses Horner's method for efficient computation: P(t) = ((p0*t + p1)*t + p2)*t + p3.
    func evaluatePolynomial(p0, p1, p2, p3: Vector2, t: f32)->Vector2
    {
        // Using Horner's method: P(t) = ((p0*t + p1)*t + p2)*t + p3
        return Vector2{x: ((p0.x * t + p1.x) * t + p2.x) * t + p3.x, y: ((p0.y * t + p1.y) * t + p2.y) * t + p3.y}
    }

    // Evaluate a quadratic Bézier curve at parameter 't'.
    // Formula: (1-t)²start + 2t(1-t)ctrl + t²end where 't' ranges from 0.0 to 1.0.
    func evaluateBezier(start, end, ctrl: Vector2, t: f32)->Vector2
    {
        let it  = 1.0 - t
        let it2 = it * it
        let t2  = t * t

        // Quadratic Bézier: (1-t)²start + 2t(1-t)ctrl + t²end
        let a = it2              // (1-t)²
        let b = 2.0 * t * it     // 2t(1-t)
        let c = t2               // t²

        return Vector2{x: a * start.x + b * ctrl.x + c * end.x, y: a * start.y + b * ctrl.y + c * end.y}
    }

    // Evaluate a cubic Bézier curve at parameter 't'.
    // Formula: (1-t)³start + 3t(1-t)²ctrl1 + 3t²(1-t)ctrl2 + t³end where 't' ranges from 0.0 to 1.0.
    func evaluateBezier(start, end, ctrl1, ctrl2: Vector2, t: f32)->Vector2
    {
        let it  = 1.0 - t
        let t2  = t * t
        let it2 = it * it

        // Use Horner's method for more efficient computation
        let a = it2 * it          // (1-t)³
        let b = 3.0 * t * it2     // 3t(1-t)²
        let c = 3.0 * t2 * it     // 3t²(1-t)
        let d = t2 * t            // t³

        return Vector2{x: a * start.x + b * ctrl1.x + c * ctrl2.x + d * end.x, y: a * start.y + b * ctrl1.y + c * ctrl2.y + d * end.y}
    }

    // Find roots of quadratic equation ax² + bx + c = 0 within the range [0, 1].
    // Returns an array containing valid roots that fall within the parameter range.
    internal func solveQuadratic(a: f32, b: f32, c: f32)->Array'f32
    {
        var roots: Array'f32

        if Math.abs(a) < 1e-6
        {
            // Linear case: bx + c = 0
            if Math.abs(b) > 1e-6
            {
                let root = -c / b
                if root >= 0.0 and root <= 1.0 do
                    roots.add(root)
            }
        }
        else
        {
            // Quadratic case
            let discriminant = b * b - 4.0 * a * c
            if discriminant >= 0.0
            {
                let sqrtD = Math.sqrt(discriminant)
                let root1 = (-b + sqrtD) / (2.0 * a)
                let root2 = (-b - sqrtD) / (2.0 * a)

                if root1 >= 0.0 and root1 <= 1.0 do
                    roots.add(root1)
                if root2 >= 0.0 and root2 <= 1.0 do
                    roots.add(root2)
            }
        }

        return roots
    }

    // Calculate the axis-aligned bounding box of a cubic Bézier curve.
    // Finds extrema by solving the derivative equation and evaluating the curve at critical points.
    func bezierBounds(start, end, ctrl0, ctrl1: Vector2)->Rectangle
    {
        // Start with endpoints
        var minX = Math.min(start.x, end.x)
        var maxX = Math.max(start.x, end.x)
        var minY = Math.min(start.y, end.y)
        var maxY = Math.max(start.y, end.y)

        // Find extrema by solving derivative = 0
        // For cubic Bézier B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
        // Derivative B'(t) = 3[(1-t)²(P₁-P₀) + 2(1-t)t(P₂-P₁) + t²(P₃-P₂)]
        // Which simplifies to: B'(t) = at² + bt + c where:

        // For X component:
        let ax = 3.0 * (end.x - 3.0 * ctrl1.x + 3.0 * ctrl0.x - start.x)
        let bx = 6.0 * (ctrl1.x - 2.0 * ctrl0.x + start.x)
        let cx = 3.0 * (ctrl0.x - start.x)

        let xRoots = solveQuadratic(ax, bx, cx)
        for t in xRoots
        {
            let point = evaluateBezier(start, end, ctrl0, ctrl1, t)
            minX = Math.min(minX, point.x)
            maxX = Math.max(maxX, point.x)
        }

        // For Y component:
        let ay = 3.0 * (end.y - 3.0 * ctrl1.y + 3.0 * ctrl0.y - start.y)
        let by = 6.0 * (ctrl1.y - 2.0 * ctrl0.y + start.y)
        let cy = 3.0 * (ctrl0.y - start.y)

        let yRoots = solveQuadratic(ay, by, cy)
        for t in yRoots
        {
            let point = evaluateBezier(start, end, ctrl0, ctrl1, t)
            minY = Math.min(minY, point.y)
            maxY = Math.max(maxY, point.y)
        }

        return Rectangle{minX, minY, maxX - minX, maxY - minY}
    }

    // Calculate the axis-aligned bounding box of a quadratic Bézier curve.
    // Finds extrema by solving the linear derivative equation for critical points.
    func bezierBounds(start, end, ctrl: Vector2)->Rectangle
    {
        // Start with endpoints
        var minX = Math.min(start.x, end.x)
        var maxX = Math.max(start.x, end.x)
        var minY = Math.min(start.y, end.y)
        var maxY = Math.max(start.y, end.y)

        // Find extrema by solving derivative = 0
        // For quadratic Bézier B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
        // Derivative B'(t) = 2[(1-t)(P₁-P₀) + t(P₂-P₁)]
        // Which simplifies to: B'(t) = 2[P₀ - 2P₁ + P₂]t + 2[P₁ - P₀]
        // Setting to zero: at + b = 0, where a = 2(P₀ - 2P₁ + P₂), b = 2(P₁ - P₀)

        // For X component:
        let ax = 2.0 * (start.x - 2.0 * ctrl.x + end.x)
        let bx = 2.0 * (ctrl.x - start.x)

        if Math.abs(ax) > 1e-6
        {
            let t = -bx / ax
            if t >= 0.0 and t <= 1.0
            {
                let point = evaluateBezier(start, end, ctrl, t)
                minX = Math.min(minX, point.x)
                maxX = Math.max(maxX, point.x)
            }
        }

        // For Y component:
        let ay = 2.0 * (start.y - 2.0 * ctrl.y + end.y)
        let by = 2.0 * (ctrl.y - start.y)

        if Math.abs(ay) > 1e-6
        {
            let t = -by / ay
            if t >= 0.0 and t <= 1.0
            {
                let point = evaluateBezier(start, end, ctrl, t)
                minY = Math.min(minY, point.y)
                maxY = Math.max(maxY, point.y)
            }
        }

        return Rectangle{minX, minY, maxX - minX, maxY - minY}
    }
}

// Every classic curve, built once so that reading one costs nothing.
private var g_CurvePresets: [CurvePreset] Curve

// Fills the shared preset table before any application code runs, so the first animation of a
// program does not pay for it and no evaluation ever has to lock.
#init
{
    for preset in CurvePreset do
        g_CurvePresets[preset] = Curve.create(preset)
}
