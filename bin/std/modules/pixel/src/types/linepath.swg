using Core, Core.Math

// Identifies the segment encoded by one [[Pixel.Element]].
public enum ElementType
{
    Line        // Straight segment ending at `position`.
    Arc         // Elliptical arc encoded by center, angle, and radius data.
    Bezier1     // Quadratic Bézier segment with one control point.
    Bezier2     // Cubic Bézier segment with two control points.
    Curve       // Smoothed curve point interpreted with neighboring elements.
}

// Stores one compact segment in a [[Pixel.LinePath]].
public struct Element
{
    public
    {
        type:     ElementType = undefined     // Segment representation.
        position: Vector2                     // Endpoint, or center for an arc.
        p1:       Vector2                     // First control point, or arc angle interval.
        p2:       Vector2                     // Second control point, or arc radii.
    }
}

// Builds a mutable vector path from lines, arcs, and Bézier curves.
//
// A path begins with [[LinePath.start]]. Segment methods update `endPoint`;
// [[LinePath.close]] optionally joins the last point to the first. Flattened
// polygons and triangles are cached and invalidated by geometry changes.
//
// ## Example
//
// ```swag
// var path: LinePath
// path.start(12, 12)
// path.lineTo(84, 12)
// path.lineTo(48, 72)
// path.close()
// ```
public struct LinePath
{
    public readonly
    {
        elements:   Array'Element     // Ordered segments after the starting point.
        startPoint: Vector2           // First point in path-space pixels.
        endPoint:   Vector2           // Current last point in path-space pixels.
        isClosed:   bool              // Whether the path forms a closed contour.
    }

    // Flattening cache, rebuilt from the segments whenever the path or the quality changes.
    // Call 'flatten' and read the result through the accessors; the cache is not an input.

    internal
    {
        isDirty:          bool                // Whether cached flattened geometry is stale.
        serial:           s32                 // Group identifier used by path-list boolean operations.
        flattenTolerance: f32                 // Tolerance used to build the current flattened cache, in path units.
        isPolyOnly:       bool                // Whether every segment is already polygonal.
        isFlatten:        bool                // Whether flattened geometry is available.
        revision:         u64                 // Advances whenever the flattened contour changes; keys derived caches.
        minBounds:        Vector2             // Minimum cached path bound.
        maxBounds:        Vector2             // Maximum cached path bound.
        endPosBuffer:     Vector2             // Reusable endpoint workspace for flattening.
        polygon:          Polygon             // Cached flattened contour.
        triangles:        Poly2Tri.Result     // Cached fill tessellation.

        // Outward direction of every tessellation vertex that came from a contour, and zero for
        // one the tessellator introduced. A fill insets its solid along these so its edge can be
        // placed by the antialiasing band rather than by the triangulation, and they are cached
        // beside the triangulation because they describe exactly its vertices.
        triangleOffsets: Array'Vector2
    }
}

// Source of contour revisions, shared by every path of the process.
//
// A revision identifies one state of one flattened contour, so a cache keyed by it can never
// read a stale entry: the counter only moves forward, and a rebuilt contour always takes a
// value no contour has carried before — a path cleared and rebuilt identically included.
private var g_ContourRevision: u64

private func nextContourRevision()->u64 => Swag.atomadd(&g_ContourRevision, 1) + 1

public impl LinePath
{
    // Releases cached tessellation when the path leaves scope.
    mtd opDrop()
    {
        .clearCache()
    }

    // Detaches cached tessellation after copying the path.
    mtd opPostCopy()
    {
        .triangles.clear()
        .triangleOffsets.clear()
    }

    // Releases all cached polygon and tessellation data.
    internal mtd clearCache()
    {
        .triangles.clear()
        .triangleOffsets.clear()
        .polygon.clear()
        .isFlatten = false
        .isDirty   = true
        .revision  = nextContourRevision()
    }

    // Releases all path geometry and restores an empty value.
    mtd clear()
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)
    }

    // Clears the path and starts a new open contour at `(startX, startY)`.
    mtd start(startX, startY: f32)
    {
        .elements.clear()
        .isClosed   = false
        .isDirty    = true
        .isPolyOnly = false
        .startPoint = Vector2{startX, startY}
        .endPoint   = .startPoint
    }

    // Adds a straight segment from the current endpoint to `(x, y)`.
    mtd lineTo(x, y: f32)
    {
        let newEndPoint = Vector2{x, y}
        if newEndPoint.isEqualEpsilon(.endPoint) do
            return

        var elem: Element = undefined
        elem.type = .Line
        elem.position.set(x, y)
        .elements.add(elem)
        .endPoint = newEndPoint
        .isDirty  = true
    }

    // Adds a smoothed curve point at `(x, y)`.
    mtd curveTo(x, y: f32)
    {
        let newEndPoint = Vector2{x, y}
        if newEndPoint.isEqualEpsilon(.endPoint) do
            return

        var elem: Element = undefined
        elem.type = .Curve
        elem.position.set(x, y)
        .elements.add(elem)
        .endPoint = newEndPoint
        .isDirty  = true
    }

    // Adds a quadratic Bézier ending at `(x, y)` with one control point.
    mtd bezierTo(x, y: f32, ctx, cty: f32)
    {
        let newEndPoint = Vector2{x, y}
        if newEndPoint.isEqualEpsilon(.endPoint) do
            return

        var elem: Element = undefined
        elem.type = .Bezier1
        elem.position.set(x, y)
        elem.p1.set(ctx, cty)
        .elements.add(elem)
        .endPoint = newEndPoint
        .isDirty  = true
    }

    // Adds a cubic Bézier ending at `(x, y)` with two control points.
    mtd bezierTo(x, y: f32, ct1x, ct1y: f32, ct2x, ct2y: f32)
    {
        let newEndPoint = Vector2{x, y}
        if newEndPoint.isEqualEpsilon(.endPoint) do
            return

        var elem: Element = undefined
        elem.type = .Bezier2
        elem.position.set(x, y)
        elem.p1.set(ct1x, ct1y)
        elem.p2.set(ct2x, ct2y)
        .elements.add(elem)
        .endPoint = newEndPoint
        .isDirty  = true
    }

    // Add an arc from the previous point
    mtd arcTo(centerX, centerY: f32, radiusX, radiusY: f32, initAngle, maxAngle: Math.Angle)
    {
        var ia = initAngle.radians
        while ia < 0 do
            ia += Math.ConstF32.TwoPi
        var ma = maxAngle.radians
        while ma < 0 do
            ma += Math.ConstF32.TwoPi
        while ma < ia do
            ma += Math.ConstF32.TwoPi

        let newEndPoint = Vector2{centerX + (Math.sin(ma) * radiusX), centerY + (-Math.cos(ma) * radiusY)}
        if newEndPoint.isEqualEpsilon(.endPoint) do
            return

        var elem: Element = undefined
        elem.type = .Arc
        elem.position.set(centerX, centerY)

        elem.p1.x = ia
        elem.p1.y = ma

        elem.p2.x = radiusX
        elem.p2.y = radiusY
        .elements.add(elem)
        .isDirty = true

        .endPoint = newEndPoint
    }

    // Returns the rectangle enclosing every point that defines this path.
    //
    // A Bézier is contained by its control polygon and an arc by its centre and radii, so
    // this answers without flattening anything: it works on a path still being built, and
    // costs one pass over the segments. The result can be wider than the ink the path
    // finally lays down, and is never narrower — which is what makes it safe to reject
    // work against, and unsuitable for measuring a drawing.
    //
    // ```swag
    // if !path.controlBounds().intersects(dirtyRect) do
    //     return
    // ```
    mtd const controlBounds()->Math.Rectangle
    {
        var min = .startPoint
        var max = .startPoint

        for element in .elements
        {
            if element.type == .Arc
            {
                // An arc stores its centre, its angle interval, and its radii, so the
                // circle around the centre is the bound that holds for every interval.
                let radius = Vector2{Math.abs(element.p2.x), Math.abs(element.p2.y)}
                min = Vector2.min(min, element.position - radius)
                max = Vector2.max(max, element.position + radius)
                continue
            }

            min = Vector2.min(min, element.position)
            max = Vector2.max(max, element.position)
            if element.type == .Bezier1 or element.type == .Bezier2
            {
                min = Vector2.min(min, element.p1)
                max = Vector2.max(max, element.p1)
            }

            if element.type == .Bezier2
            {
                min = Vector2.min(min, element.p2)
                max = Vector2.max(max, element.p2)
            }
        }

        return {min.x, min.y, max.x - min.x, max.y - min.y}
    }

    // Close the figure
    // Will add a line or a curve to the first point if necessary
    mtd close()
    {
        if .isClosed or !.elements.count do
            return

        let v = .endPoint - .startPoint
        if v.lengthSquared() >= 0.5 * 0.5
        {
            if .elements.backPtr().type == .Curve do
                .curveTo(.startPoint.x, .startPoint.y)
            else do
                .lineTo(.startPoint.x, .startPoint.y)
        }

        .isClosed = true
        .isDirty  = true
    }

    // Marks geometry produced by a trusted contour source as closed without
    // inserting an explicit closing segment.
    internal mtd assumeClosed()
    {
        .isClosed = true
        .isDirty  = true
    }

    // Records that the flattened contour was modified in place, so caches keyed on its
    // revision rebuild without the cost of a full recompute.
    internal mtd touchContour()
    {
        .revision = nextContourRevision()
    }

    // Adopts the already-populated polygon cache as the complete path geometry.
    internal mtd adoptGeneratedPolygon()
    {
        .isPolyOnly = true
        .assumeClosed()
        .isDirty   = false
        .isFlatten = true
        .revision  = nextContourRevision()
        .minBounds = .polygon.minBounds
        .maxBounds = .polygon.maxBounds

        if .polygon.points.count
        {
            .startPoint = .polygon.pointAt(0)[]
            .endPoint   = .startPoint
        }
    }

    // Initialize the path with a rectangle at exact coordinates.
    //
    // Unlike [[setRect]], nothing is snapped to the pixel grid: authored fractional
    // geometry, such as a parsed vector document, stays untouched.
    mtd setRectRaw(l, t, w, h: f32)
    {
        let r = l + w
        let b = t + h

        .start(l, t)
        .lineTo(r, t)
        .lineTo(r, b)
        .lineTo(l, b)
        .lineTo(l, t)
        .close()
    }

    // Initialize the path with a rectangle
    mtd setRect(left, top, width, height: f32)
    {
        let l = Math.round(left)
        let t = Math.round(top)
        let w = Math.round(width)
        let h = Math.round(height)

        .setRectRaw(l, t, w, h)
    }

    // Initialize the path with a round rectangle at exact coordinates.
    //
    // Unlike [[setRoundRect]], nothing is snapped to the pixel grid; the radii are
    // clamped to half the dimensions, so a full radius produces a capsule.
    mtd setRoundRectRaw(l, t, w, h: f32, radiusX, radiusY: f32)
    {
        let r  = l + w
        let b  = t + h
        let rX = Math.max(Math.min(radiusX, w * 0.5), 0.0)
        let rY = Math.max(Math.min(radiusY, h * 0.5), 0.0)

        .start(l, t + rY)
        .arcTo(l + rX, t + rY, rX, rY, 270'deg, 360'deg)
        .lineTo(r - rX, t)
        .arcTo(r - rX, t + rY, rX, rY, 0'deg, 90'deg)
        .lineTo(r, b - rY)
        .arcTo(r - rX, b - rY, rX, rY, 90'deg, 180'deg)
        .lineTo(l + rX, b)
        .arcTo(l + rX, b - rY, rX, rY, 180'deg, 270'deg)
        .close()
    }

    // Initialize the path with a round rectangle
    mtd setRoundRect(left, top, width, height: f32, radiusX, radiusY: f32)
    {
        let l = Math.round(left)
        let t = Math.round(top)
        let w = Math.round(width)
        let h = Math.round(height)

        .setRoundRectRaw(l, t, w, h, Math.round(radiusX), Math.round(radiusY))
    }

    // Initialize the path with an ellipse at exact coordinates.
    //
    // Unlike [[setEllipse]], the center and radii are not snapped to the pixel grid.
    mtd setEllipseRaw(cX, cY: f32, rX, rY: f32)
    {
        .start(cX, cY - rY)
        .arcTo(cX, cY, rX, rY, 0'deg, 90'deg)
        .arcTo(cX, cY, rX, rY, 90'deg, 180'deg)
        .arcTo(cX, cY, rX, rY, 180'deg, 270'deg)
        .arcTo(cX, cY, rX, rY, 270'deg, 360'deg)
        .close()
    }

    // Initialize the path with an ellipse
    mtd setEllipse(centerX, centerY: f32, radiusX, radiusY: f32)
    {
        let cX = Math.round(centerX)
        let cY = Math.round(centerY)
        let rX = 0.5 * Math.round(radiusX * 2)
        let rY = 0.5 * Math.round(radiusY * 2)

        .setEllipseRaw(cX, cY, rX, rY)
    }

    // Initialize the path with a circle
    mtd setCircle(centerX, centerY: f32, radius: f32)
    {
        let cX = Math.round(centerX)
        let cY = Math.round(centerY)
        let r  = 0.5 * Math.round(radius * 2)

        .start(cX, cY - r)
        .arcTo(cX, cY, r, r, 0'deg, 90'deg)
        .arcTo(cX, cY, r, r, 90'deg, 180'deg)
        .arcTo(cX, cY, r, r, 180'deg, 270'deg)
        .arcTo(cX, cY, r, r, 270'deg, 360'deg)
        .close()
    }

    // Initialize the path with an arc
    mtd setArc(centerX, centerY: f32, radius: f32, startAngle, endAngle: Math.Angle)
    {
        if isZeroEpsilon(endAngle.radians - startAngle.radians) do
            return

        let cX = Math.round(centerX)
        let cY = Math.round(centerY)
        let r  = Math.round(radius)

        var startPos = Math.Vector2{0, -r}
        startPos.rotateBy(startAngle)
        .start(cX + startPos.x, cY + startPos.y)

        var s = startAngle.radians
        var m = 0'f32
        if s < Math.ConstF32.PiBy2
        {
            m = Math.min(endAngle.radians, Math.ConstF32.PiBy2)
            .arcTo(cX, cY, r, r, s, m)
            s = m
        }

        if s < Math.ConstF32.Pi
        {
            m = Math.min(endAngle.radians, Math.ConstF32.Pi)
            .arcTo(cX, cY, r, r, s, m)
            s = m
        }

        if s < Math.ConstF32.Pi + Math.ConstF32.PiBy2
        {
            m = Math.min(endAngle.radians, Math.ConstF32.Pi + Math.ConstF32.PiBy2)
            .arcTo(cX, cY, r, r, s, m)
            s = m
        }

        if s < Math.ConstF32.TwoPi
        {
            m = Math.min(endAngle.radians, Math.ConstF32.TwoPi)
            .arcTo(cX, cY, r, r, s, m)
        }
    }

    // Flattens the path as needed and returns its mutable cached contour.
    //
    // Mutating the returned points changes only the cache. Call
    // [[Pixel.LinePath.recomputeFlattenedPolygon]] after geometric edits; a
    // later path edit may replace the contour completely.
    mtd flattenedPolygon(quality = PaintQuality.Normal)->*Polygon
    {
        .flatten(quality)
        return &.polygon
    }

    // Refreshes bounds and polygon properties after editing the flattened contour.
    mtd recomputeFlattenedPolygon()
    {
        .polygon.recompute()
        .minBounds = .polygon.minBounds
        .maxBounds = .polygon.maxBounds
        .triangles.clear()
        .triangleOffsets.clear()
        .revision = nextContourRevision()
    }

    // Convert the path to a list of points
    //
    // `scale` is the number of device pixels one path unit covers when the result is drawn:
    // the flattening tolerance is expressed in path units, so a curve zoomed by a transform
    // needs proportionally more segments to look as smooth on screen as it does at scale one.
    // The cache keeps the finest flattening produced so far, whichever combination of quality
    // and scale asked for it.
    mtd flatten(quality = PaintQuality.Normal, scale = 1.0'f32)
    {
        // Already done ?
        if .isPolyOnly do
            return
        let tolerance = getFlattenDistance(quality) / Math.max(scale, 1.0)
        if !.isDirty and .isFlatten and .flattenTolerance <= tolerance do
            return

        .clearCache()
        .isDirty               = false
        .isFlatten             = true
        .flattenTolerance      = tolerance
        .minBounds, .maxBounds = .startPoint

        if !.elements.count do
            return

        .endPosBuffer = .startPoint
        .polygon.points.add(.endPosBuffer)

        for elem, i in .elements
        {
            let pos = elem.position

            switch #complete elem.type
            {
            case .Line:    .flattenLine(pos)
            case .Bezier1: .flattenBezier(pos, elem.p1, tolerance)
            case .Bezier2: .flattenBezier(pos, elem.p1, elem.p2, tolerance)
            case .Curve:   .flattenCurve(pos, i, tolerance)
            case .Arc:     .flattenArc(pos, elem.p1, elem.p2, tolerance)
            }
        }

        .polygon.recompute()
    }
}

impl LinePath
{
    func getFlattenDistance(quality: PaintQuality)->f32
    {
        var minDist = 0'f32
        switch quality
        {
        case .Draft:  minDist = 1
        case .Normal: minDist = 0.2
        case .High:   minDist = 0.05
        }

        return minDist
    }

    mtd flattenLine(pos: Vector2)
    {
        // Curve subdivision and authored paths can land two consecutive samples on
        // the same spot; a coincident point draws nothing, breaks stroke joins, and
        // degenerates fill triangulation, so it is never emitted.
        if .polygon.points.count and Math.abs(pos.x - .endPosBuffer.x) < 0.0001 and Math.abs(pos.y - .endPosBuffer.y) < 0.0001 do
            return

        .minBounds = Vector2.min(.minBounds, pos)
        .maxBounds = Vector2.max(.maxBounds, pos)
        .polygon.add(pos)
        .endPosBuffer = pos
    }

    mtd flattenCurve(pos: Math.Vector2, i: u64, tolerance: f32)
    {
        var p0, p1, p2, p3: Vector2 = undefined
        let lastElem                = .elements.count - 1

        if lastElem <= 1
        {
            .flattenLine(pos)
            return
        }

        if i == 0
        {
            p0 = .isClosed ? .elements[lastElem - 1].position : (.startPoint - pos) + .startPoint
            p1 = .startPoint
            p2 = pos
            p3 = .elements[i + 1].position
        }
        elif i < lastElem
        {
            p0 = i == 1 ? .startPoint : .elements[i - 2].position
            p1 = .elements[i - 1].position
            p2 = pos
            p3 = .elements[i + 1].position
        }
        else
        {
            p0 = .elements[i - 2].position
            p1 = .elements[i - 1].position
            p2 = pos
            p3 = .isClosed ? .elements[1].position : pos + (pos - p1)
        }

        const Alpha   = 0.5
        const Tension = 0.0

        let t01 = Math.pow(Vector2.distanceTo(p0, p1), Alpha)
        let t12 = Math.pow(Vector2.distanceTo(p1, p2), Alpha)
        let t23 = Math.pow(Vector2.distanceTo(p2, p3), Alpha)

        let m1 = (1.0 - Tension) * (p2 - p1 + t12 * ((p1 - p0) / t01 - (p2 - p0) / (t01 + t12)))
        let m2 = (1.0 - Tension) * (p2 - p1 + t12 * ((p3 - p2) / t23 - (p3 - p1) / (t12 + t23)))

        let sa = 2.0 * (p1 - p2) + m1 + m2
        let sb = -3.0 * (p1 - p2) - m1 - m1 - m2
        let sc = m1
        let sd = p1
        .flattenCurve(sa, sb, sc, sd, tolerance)
    }

    mtd flattenCurve(p0, p1, p2, p3: Vector2, tolerance: f32)
    {
        let startPt = .endPosBuffer
        let endPt   = p0 + p1 + p2 + p3     // Point at t=1

        // Calculate optimal number of segments analytically
        let numSegments = calculateCubicPolynomialSegments(p0, p1, p2, p3, startPt, endPt, tolerance)

        if numSegments <= 1
        {
            // Curve is flat enough, just draw direct line
            .flattenLine(endPt)
            return
        }

        let stepSize = 1.0 / numSegments

        // Generate all points in one pass using optimized polynomial evaluation
        for i in 1 to numSegments
        {
            let t     = stepSize * i
            let point = Math.Curve.evaluatePolynomial(p0, p1, p2, p3, t)
            .flattenLine(point)
        }
    }

    // Calculate optimal number of segments for cubic polynomial
    func calculateCubicPolynomialSegments(p0, p1, p2, p3: Vector2, startPt, endPt: Vector2, tolerance: f32)->u32
    {
        // Calculate chord length
        let chordLength = startPt.distanceTo(endPt)

        if chordLength < tolerance do
            return 1     // Very short curve

        // For cubic polynomials, we need to estimate maximum curvature
        // Sample a few points to get an approximation of maximum deviation
        var maxDeviation = 0.0

        // Sample at critical points: t = 0.25, 0.5, 0.75
        let samplePoints = [0.25, 0.5, 0.75]

        for t in samplePoints
        {
            let point     = Curve.evaluatePolynomial(p0, p1, p2, p3, t)
            let deviation = Geometry.distanceFromPointToLine(point, startPt, endPt)
            maxDeviation = Math.max(maxDeviation, deviation)
        }

        if maxDeviation < tolerance
        {
            return 1     // Curve is already flat enough
        }

        // Estimate segments needed based on maximum deviation
        // For cubic curves, use a conservative estimate
        let segments = Math.ceil(Math.sqrt(maxDeviation / tolerance) * 3.0)

        return cast(u32) Math.max(1, Math.min(segments, 1000))     // Reasonable bounds
    }

    ///////////////////////////////

    mtd flattenBezier(pos, p1: Vector2, tolerance: f32)
    {
        let startPt = .endPosBuffer

        // Calculate optimal number of segments analytically
        let numSegments = calculateQuadraticBezierSegments(startPt, p1, pos, tolerance)

        if numSegments <= 1
        {
            // Curve is flat enough, just draw direct line
            .flattenLine(pos)
            return
        }

        let stepSize = 1.0 / numSegments

        // Generate all points in one pass using optimized quadratic Bézier evaluation
        for i in 1 to numSegments
        {
            let t     = stepSize * i
            let point = Math.Curve.evaluateBezier(startPt, pos, p1, t)
            .flattenLine(point)
        }
    }

    // Calculate optimal number of segments for quadratic Bézier
    func calculateQuadraticBezierSegments(p0, p1, p2: Vector2, tolerance: f32)->u32
    {
        // For quadratic Bézier, the maximum deviation occurs at the control point
        // Calculate distance from control point to chord line
        let deviation = Geometry.distanceFromPointToLine(p1, p0, p2)

        if deviation < tolerance do
            return 1     // Curve is already flat enough

        // For quadratic curves, the relationship is more direct
        // Maximum error ≈ deviation / 8 per segment
        // So segments needed ≈ sqrt(8 * deviation / tolerance)
        let segments = Math.ceil(Math.sqrt(8.0 * deviation / tolerance))

        return cast(u32) Math.max(1, Math.min(segments, 1000))     // Reasonable bounds
    }

    ///////////////////////////////

    mtd flattenBezier(pos, p1, p2: Vector2, tolerance: f32)
    {
        let startPt = .endPosBuffer

        // Calculate optimal number of segments analytically
        let numSegments = calculateBezierSegments(startPt, p1, p2, pos, tolerance)

        if numSegments <= 1
        {
            // Curve is flat enough, just draw direct line
            .flattenLine(pos)
            return
        }

        let stepSize = 1.0 / numSegments

        // Generate all points in one pass using optimized Bézier evaluation
        for i in 1 to numSegments
        {
            let t     = stepSize * i
            let point = Math.Curve.evaluateBezier(startPt, pos, p1, p2, t)
            .flattenLine(point)
        }
    }

    // Calculate optimal number of segments using curvature analysis
    func calculateBezierSegments(p0, p1, p2, p3: Vector2, tolerance: f32)->u32
    {
        // Calculate the maximum curvature using the control polygon method
        // This is much faster than iterative subdivision

        // Vector from start to end
        let chord       = Vector2{x: p3.x - p0.x, y: p3.y - p0.y}
        let chordLength = chord.length()

        if chordLength < tolerance do
            return 1     // Very short curve

        // Calculate maximum deviation of control points from chord
        var maxDeviation = 0.0

        // Distance from p1 to chord line
        let dev1 = Geometry.distanceFromPointToLine(p1, p0, p3)
        maxDeviation = Math.max(maxDeviation, dev1)

        // Distance from p2 to chord line
        let dev2 = Geometry.distanceFromPointToLine(p2, p0, p3)
        maxDeviation = Math.max(maxDeviation, dev2)

        if maxDeviation < tolerance
        {
            return 1     // Curve is already flat enough
        }

        // Use the flatness criterion: segments ≈ sqrt(maxDeviation / tolerance)
        let segments = Math.ceil(Math.sqrt(maxDeviation / tolerance) * 2.0)

        return cast(u32) Math.max(1, Math.min(segments, 1000))     // Reasonable bounds
    }

    ///////////////////////////////

    mtd flattenArc(pos, p1, p2: Vector2, tolerance: f32)
    {
        let angleSpan = p1.y - p1.x
        let radius    = Math.max(p2.x, p2.y)     // Use the larger radius component

        // Calculate required number of segments analytically
        let numSegments = calculateFlattenArcSegments(angleSpan, radius, tolerance)

        if numSegments <= 1
        {
            // Arc is small enough, just draw direct line to end
            let endPos = Vector2{x: pos.x + (Math.sin(p1.y) * p2.x), y: pos.y - (Math.cos(p1.y) * p2.y)}
            .flattenLine(endPos)
            return
        }

        let angleStep = angleSpan / numSegments

        // Generate all points in one pass
        for i in 1 to numSegments
        {
            let angle = p1.x + (angleStep * i)
            let point = Vector2{x: pos.x + (Math.sin(angle) * p2.x), y: pos.y - (Math.cos(angle) * p2.y)}
            .flattenLine(point)
        }
    }

    // Calculate optimal number of segments based on arc properties
    func calculateFlattenArcSegments(angleSpan: f32, radius: f32, tolerance: f32)->u32
    {
        if radius < 0.1 do
            return 1

        // Use the sagitta formula: segments = ceil(angle / (2 * acos(1 - tolerance/radius)))
        // This gives us the minimum segments needed to stay within tolerance
        var maxAnglePerSegment = 2.0 * Math.acos(1.0 - Math.min(tolerance / radius, 1.0))

        // Clamp to reasonable bounds
        maxAnglePerSegment = Math.max(maxAnglePerSegment, 0.01)                // Minimum angle
        maxAnglePerSegment = Math.min(maxAnglePerSegment, ConstF32.Pi / 4)     // Maximum angle (45°)

        let numSegments = Math.ceil(Math.abs(angleSpan) / maxAnglePerSegment)

        return cast(u32) Math.max(1, Math.min(numSegments, 1000))     // Reasonable bounds
    }
}
