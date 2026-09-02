using Core, Core.Math

// Selects how a path made of several contours decides which regions it encloses.
//
// Both rules count how many times the contours wind around a point, and differ only in what
// they conclude from that count. Neither depends on the direction a contour happens to run,
// which is what separates them from the convention [[Pixel.Painter.fillPath]] reads without
// a rule.
public enum PathFillRule
{
    NonZero     // Inside wherever the winding count is not zero.
    EvenOdd     // Inside wherever the winding count is odd.
}

// Identifies one contour point by its exact coordinates. The tessellator copies the points it is
// given, so the two bit patterns are the same value and not merely a close one.
private func contourPointKey(point: Vector2)->u64
{
    return cast(u64) cast #bit(u32) point.x << 32 | cast(u64) cast #bit(u32) point.y
}

public impl Painter
{
    // Records, for every vertex of a freshly tessellated region, the outward direction of the
    // contour point it came from, so the solid can be inset when it is pushed rather than when it
    // is built.
    //
    // The tessellator answers with plain positions, and a constrained triangulation of contours
    // that were already normalized introduces no point of its own, so each vertex is one of the
    // contour points and is found by its exact coordinates. A vertex that is not — a tessellator
    // that decided otherwise — keeps a zero direction and stays where it is. The lookup reuses the
    // painter's own table: a page of vector glyphs tessellates thousands of regions, and a fresh
    // table for each of them is a page's worth of allocation for nothing.
    private mtd buildTriangleOffsets(p: *LinePath, island: const [..] *LinePath)
    {
        p.triangleOffsets.clear()
        p.triangleOffsets.resize(p.triangles.vertices.count)

        .sharedDirections.clear()
        for contour in island
        {
            contour.polygon.fillOffsetDirections(&.sharedOffsetDirs)
            let points = contour.polygon.points.buffer!
            let dirs   = .sharedOffsetDirs.buffer!

            // The first direction filed under a position is the one that stands, which is what
            // asking the table before writing used to express in two probes instead of one.
            for i in contour.polygon.points.count do
                .sharedDirections.add(contourPointKey(points[i]), dirs[i], updateValue: false)
        }

        for i in p.triangles.vertices.count
        {
            let found = .sharedDirections.tryFind(contourPointKey(p.triangles.vertices[i]))
            if found do
                p.triangleOffsets[i] = found!.value
        }
    }

    // Emit a connected, mitered antialiasing fringe ring around a closed polygon
    // contour. Adjacent edges share their mitered inner/outer vertices, so corners
    // stay seamless (no per-edge wedges).
    //
    // 'innerOff'/'outerOff' place the full-coverage (cov=1) and zero-coverage (cov=0)
    // rings relative to the contour. A centered band (-AAHalf / +AAHalf) is what keeps a
    // shape the size it states, and both fills use it wherever the colour channels decide
    // the edge. The non-convex fill cannot inset its cached triangulation, so on a
    // paintAlpha render target — whose alpha is rebuilt by replaying the draws under a
    // maximum, which keeps the solid's own hard edge — it places the band fully outside
    // (0 / 2*AAHalf) instead, so the full-coverage ring coincides with that edge and one
    // clean outward ramp survives the maximum.
    private mtd fillContourAA(polygon: *Polygon, color: Color, innerOff: f32, outerOff: f32)
    {
        let count = polygon.points.count - 1
        if count < 2 do
            return

        // Where a point moves to is a miter — two normalizations and a line intersection — and it
        // does not depend on how far it moves: the offset only scales it. The ring asked for it
        // four times per edge, and every point is one edge's start and the previous edge's end,
        // so a contour paid eight miters per point where it needs one. It is resolved once here
        // and every corner of the band is that direction scaled.
        polygon.fillOffsetDirections(&.sharedOffsetDirs)

        let argb = color.argb
        let dirs = .sharedOffsetDirs.buffer!
        for i in count
        {
            let j  = (i + 1) % count
            let pi = polygon.points[i]
            let pj = polygon.points[j]
            let di = dirs[i]
            let dj = dirs[j]
            .pushFringeQuad(pi + di * innerOff, pi + di * outerOff, pj + dj * innerOff, pj + dj * outerOff, argb)
        }
    }

    private mtd fillPathTriangulated(t: #null *Poly2Tri.Tessellate, p: *LinePath, bvMin, bvMax: Vector2, brush: Brush, island: const [..] *LinePath)
    {
        .setTexture0(bvMin, bvMax, brush)
        .resetTextureFont()

        // Triangulation
        if p.triangles.vertices.isEmpty()
        {
            let tess = t!
            tess.triangulate()
            p.triangles = tess.takeResult()
            tess.clear()
            .buildTriangleOffsets(p, island)
        }

        // The solid stops half a band short of the contour and the band, centered on the
        // contour, carries the coverage from there out. A solid left on the true contour is a
        // hard edge the band can only add to, so an edge would be placed by whichever side of it
        // a pixel centre happened to fall on: that is what made a page of small vector glyphs
        // read as bold and ragged at once.
        let aa     = .aaHalfPathSpace()
        let inset  = .curState.paintParams & .Antialiased ? aa : 0
        let offset = p.triangleOffsets.count == p.triangles.vertices.count
        for i in p.triangles.triangleCount()
        {
            let vertexIndex = i * 3
            if !inset or !offset
            {
                discard .pushTriangle(p.triangles.vertices[vertexIndex], p.triangles.vertices[vertexIndex + 1], p.triangles.vertices[vertexIndex + 2], brush.color)
                continue
            }

            let v0 = p.triangles.vertices[vertexIndex] - p.triangleOffsets[vertexIndex] * inset
            let v1 = p.triangles.vertices[vertexIndex + 1] - p.triangleOffsets[vertexIndex + 1] * inset
            let v2 = p.triangles.vertices[vertexIndex + 2] - p.triangleOffsets[vertexIndex + 2] * inset
            discard .pushTriangle(v0, v1, v2, brush.color)
        }

        // Every contour of the region gets a band, not only the last one the tessellator was
        // given: a glyph is an outer contour and its counters, and a band on one of them leaves
        // every other edge as a hard step.
        if .curState.paintParams & .Antialiased
        {
            for contour in island do
                .fillContourAA(&contour.polygon, brush.color, -aa, aa)
        }
    }

    // Fill a list of paths.
    mtd fillPath(pathList: *LinePathList, color: Color)
    {
        if !pathList.paths.count do
            return

        let brush = Brush.createSolid(color)
        .fillPath(pathList, brush)
    }

    mtd fillPath(path: *LinePath, brush: Brush)
    {
        path.flatten(.curState.paintQuality, .curFlattenScale)
        if Math.isZeroEpsilon(path.polygon.perimeter) do
            return

        let polygon = &path.polygon

        // Convex shape : faster
        if polygon.isConvex
        {
            .setTexture0(path.minBounds, path.maxBounds, brush)
            .resetTextureFont()

            let count = path.polygon.points.count - 1

            // When antialiased, inset the solid by half a fringe so that the centered
            // fringe band (added afterwards) never overlaps the solid fill. This keeps
            // translucent fills clean and the silhouette at its true size.
            var so = 0'f32
            let aa = .aaHalfPathSpace()
            if .curState.paintParams & .Antialiased do
                so = -aa

            // Convex shape : 1 triangle
            if count == 3
            {
                discard .pushTriangle(polygon.offsetPointAt(0, so), polygon.offsetPointAt(1, so), polygon.offsetPointAt(2, so), brush.color)
            }

            // Convex shape : 2 triangles
            elif count == 4
            {
                let v0 = polygon.offsetPointAt(0, so)
                let v1 = polygon.offsetPointAt(1, so)
                let v2 = polygon.offsetPointAt(2, so)
                let v3 = polygon.offsetPointAt(3, so)
                discard .pushTriangle(v0, v1, v2, brush.color)
                discard .pushTriangle(v0, v2, v3, brush.color)
            }

            // Convex shape: add a triangle from the center of the shape to each pair of
            // vertices
            else
            {
                let center = Vector2{path.minBounds.x + (path.maxBounds.x - path.minBounds.x) * 0.5, path.minBounds.y + (path.maxBounds.y - path.minBounds.y) * 0.5}
                for i in count
                {
                    let v0 = polygon.offsetPointAt(i, so)
                    let v1 = polygon.offsetPointAt((i + 1) % count, so)
                    discard .pushTriangle(center, v0, v1, brush.color)
                }
            }

            if .curState.paintParams & .Antialiased do
                .fillContourAA(polygon, brush.color, -aa, aa)
        }

        // Non convex shape: complex painting (triangulation)
        else
        {
            if path.polygon.isSimple
            {
                .sharedLinePathList.paths.add(path)
                .fillPath(&.sharedLinePathList, brush)
                .sharedLinePathList.paths.count = 0
            }
            else
            {
                var res = path.polygon.cleanedPaths()
                .fillPath(&res, brush)
            }
        }
    }

    mtd fillPath(path: *LinePath, color: Color)
    {
        let brush = Brush.createSolid(color)
        .fillPath(path, brush)
    }

    // Fill a list of paths.
    // If the path is clockwise, it will be filled. If the path is anti-clockwise, it will be considered as a hole.
    mtd fillPath(pathList: *LinePathList, brush: Brush)
    {
        // Flatten all paths
        pathList.flatten(.curState.paintQuality, .curFlattenScale)

        // Poly2Tri expects simple, non-intersecting contours. Individual simplicity is not
        // enough: holes can cross or meet the outer ring or one another. The list caches both
        // the verdict and the normalized copy, so an unchanged list — a document painted once
        // per frame — decides and normalizes once, not once per fill.
        .fillPreparedPathList(pathList.normalizedFill(.NonZero, byDirection: true), brush)
    }

    // Fills a list of paths under an explicitly named fill rule.
    //
    // The plain [[Pixel.Painter.fillPath]] reads the winding *direction* of each contour: a
    // clockwise one adds ink and an anticlockwise one takes it away. That is a convenient
    // convention for geometry authored for it, but it is not what a vector document format
    // means. PDF and SVG state a rule over the winding *count*, and under it a glyph drawn
    // as outlines fills correctly whichever direction its contours happen to run — which is
    // exactly the case the direction convention gets wrong, filling in the counter of every
    // letter whose outer contour runs the unexpected way.
    //
    // The geometry is normalized under `rule` before it is filled, so the result is the
    // region the rule defines rather than the one the directions suggest.
    //
    // ```swag
    // painter.fillPath(&glyph, brush, .NonZero)
    // ```
    mtd fillPath(pathList: *LinePathList, brush: Brush, rule: PathFillRule)
    {
        pathList.flatten(.curState.paintQuality, .curFlattenScale)

        // A single simple contour encloses the same region under either rule; anything else is
        // normalized under the rule. The list caches the normalized copy against its contours'
        // revisions, so a glyph-like path with holes pays the boolean solver once, not once per
        // fill, and the copy keeps its tessellation from one frame to the next.
        .fillPreparedPathList(pathList.normalizedFill(rule == .EvenOdd ? Clipper.PolyFillType.EvenOdd : Clipper.PolyFillType.NonZero, byDirection: false), brush)
    }

    // Fills a list of paths under an explicitly named fill rule with a solid color.
    mtd fillPath(pathList: *LinePathList, color: Color, rule: PathFillRule)
    {
        .fillPath(pathList, Brush.createSolid(color), rule)
    }

    private mtd fillPreparedPathList(pathList: *LinePathList, brush: Brush)
    {
        var flush: #null *LinePath

        // Everything in the cache ?
        var serial = 0
        var dirty  = false
        for p in pathList.paths
        {
            if (p.polygon.isClockwise or serial != p.serial) and flush
            {
                if !flush.triangles.vertices.count
                {
                    dirty = true
                    break
                }

                serial = p.serial
                flush  = null
            }

            if p.polygon.points.count >= 3
            {
                flush = p
            }
        }

        // If everything has been computed, then just paint them (no need to generate polylines as 'triangulate' will not use them)
        if flush and !flush.triangles.vertices.count do
            dirty = true

        serial = 0
        flush  = null
        .sharedIsland.clear()

        for p in pathList.paths
        {
            if (p.polygon.isClockwise or serial != p.serial) and flush
            {
                serial = p.serial
                .fillPathTriangulated(dirty ? &.tess : null, flush, pathList.minBounds, pathList.maxBounds, brush, .sharedIsland.toSlice())
                .sharedIsland.clear()
                flush = null
            }

            if p.polygon.points.count >= 3
            {
                flush = p
                .sharedIsland.add(p)
                if dirty do
                    .tess.addPolyLine(p.polygon)
            }
        }

        if flush do
            .fillPathTriangulated(dirty ? &.tess : null, flush, pathList.minBounds, pathList.maxBounds, brush, .sharedIsland.toSlice())
        .sharedIsland.clear()
    }

    // Fill the polygon with the given color
    mtd fillPolygon(path: *LinePath, color: Color)
    {
        if .isInvisible(color) do
            return

        let brush = Brush.createSolid(color)
        .fillPolygon(path, brush)
    }

    // Fill the polygon with the given 'brush'
    mtd fillPolygon(path: *LinePath, brush: Brush)
    {
        if .isInvisible(brush) do
            return

        path.flatten(.curState.paintQuality, .curFlattenScale)
        if path.polygon.isConvex
        {
            .fillPath(path, brush)
        }
        else
        {
            path.polygon.assumeClockwise(true)
            let res = path.polygon.cleanedPaths()
            for p in res.paths do
                .fillPath(p, brush)
        }
    }

    // Fill the polygon with the given 'brush'
    mtd fillPolygon(points: [..] Math.Vector2, brush: Brush)
    {
        if points.count < 3 do
            return

        var path: LinePath
        path.start(points[0].x, points[0].y)
        for pt, index in points where index do
            path.lineTo(pt.x, pt.y)
        path.close()
        .fillPath(&path, brush)
    }
}
