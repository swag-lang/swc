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

// One region a fill triangulates as a unit, as a range of a companion contour array.
//
// The type identity is part of the exported [[Pixel.FillPreparer]] layout, so it is public, but
// it carries no public contract of its own.
#[Swag.NoDoc]
public struct FillRegion
{
    flush: *LinePath = undefined     // Contour the region's tessellation is cached on.
    first: u64                       // Index of the region's first contour.
    count: u64                       // Contours the region is made of.
}

// Groups the contours of a fill-prepared list into the regions a fill triangulates.
//
// A region is one outer contour and the holes that follow it: a new one opens at a contour
// winding the other way, or at a change of group. Its tessellation is cached on the last contour
// that contributes to it, which is why that contour travels with the region. A contour of fewer
// than three points bounds nothing and joins no region, but still closes the one before it.
internal func fillRegions(pathList: *LinePathList, contours: *Array'(*LinePath), regions: *Array'FillRegion)
{
    contours.clear()
    regions.clear()

    var serial = 0
    var first  = 0'u64
    var flush: #null *LinePath

    for p in pathList.paths
    {
        if (p.polygon.isClockwise or serial != p.serial) and flush
        {
            serial = p.serial
            regions.add({flush!, first, contours.count - first})
            first = contours.count
            flush = null
        }

        if p.polygon.points.count >= 3
        {
            flush = p
            contours.add(p)
        }
    }

    if flush do
        regions.add({flush!, first, contours.count - first})
}

// Returns the sign that turns a region's contour directions outward.
//
// A contour's offset directions point away from the region it bounds only when the list follows
// the convention: outers clockwise, holes anticlockwise. A ruled fill of a lone simple contour is
// the one case that reaches a tessellation unnormalized, because the rule makes the direction
// irrelevant to the region; when that contour runs anticlockwise its directions point inward, and
// both the solid's inset and the antialiasing band would place the edge a band outside the
// contour, as hard as the solid.
private func regionOutward(contours: const [..] *LinePath, ruled: bool)->f32
{
    return ruled and contours.count == 1 and !contours[0].polygon.isClockwise ? -1.0'f32 : 1.0'f32
}

// Records, for every vertex of a freshly tessellated region, the outward direction of the contour
// point it came from, so the solid can be inset when it is pushed rather than when it is built.
//
// The tessellator answers with plain positions, and a constrained triangulation of contours that
// were already normalized introduces no point of its own, so each vertex is one of the contour
// points and is found by its exact coordinates. A vertex that is not — a tessellator that decided
// otherwise — keeps a zero direction and stays where it is. `directions` is the caller's own
// table: a page of vector glyphs tessellates thousands of regions, and a fresh table for each of
// them is a page's worth of allocation for nothing.
private func buildTriangleOffsets(directions: *HashTable'(u64, Vector2), p: *LinePath, contours: const [..] *LinePath, outward: f32)
{
    p.triangleOffsets.clear()
    p.triangleOffsets.resize(p.triangles.vertices.count)

    directions.clear()
    for contour in contours
    {
        let dirs   = contour.offsetDirections()
        let points = contour.polygon.points.buffer!

        // The first direction filed under a position is the one that stands, which is what
        // asking the table before writing used to express in two probes instead of one.
        for i in contour.polygon.points.count do
            directions.add(contourPointKey(points[i]), dirs[i] * outward, updateValue: false)
    }

    for i in p.triangles.vertices.count
    {
        let found = directions.tryFind(contourPointKey(p.triangles.vertices[i]))
        if found do
            p.triangleOffsets[i] = found!.value
    }
}

// Triangulates the contours already given to `tess` and caches the result on the region.
//
// The tessellation is kept on the last contour of the region rather than on the list, because
// that is where a fill looks for it, and it is left keyed to the contours it was built from.
private func buildRegionTessellation(tess: *Poly2Tri.Tessellate, directions: *HashTable'(u64, Vector2), flush: *LinePath, contours: const [..] *LinePath, ruled: bool)
{
    tess.triangulate()
    flush.triangles = tess.takeResult()
    tess.clear()
    buildTriangleOffsets(directions, flush, contours, regionOutward(contours, ruled))
}

public impl Painter
{
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
    private mtd fillContourAA(contour: *LinePath, color: Color, innerOff: f32, outerOff: f32)
    {
        let polygon = &contour.polygon
        let count   = polygon.points.count - 1
        if count < 2 do
            return

        // Where a point moves to is a miter — two normalizations and a line intersection — and it
        // does not depend on how far it moves: the offset only scales it. The ring asked for it
        // four times per edge, and every point is one edge's start and the previous edge's end,
        // so a contour paid eight miters per point where it needs one. The contour resolves them
        // once for the state it is in, and every corner of the band is that direction scaled.
        let dirs = contour.offsetDirections()

        let argb = color.argb
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

    private mtd fillPathTriangulated(t: #null *Poly2Tri.Tessellate, p: *LinePath, bvMin, bvMax: Vector2, brush: Brush, island: const [..] *LinePath, ruled: bool)
    {
        .setTexture0(bvMin, bvMax, brush)
        .resetTextureFont()

        let outward = regionOutward(island, ruled)

        // Triangulation
        if p.triangles.vertices.isEmpty() do
            buildRegionTessellation(t!, &.sharedDirections, p, island, ruled)

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
                .fillContourAA(contour, brush.color, -aa * outward, aa * outward)
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
                .fillContourAA(path, brush.color, -aa, aa)
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
        .fillPreparedPathList(pathList.normalizedFill(.NonZero, byDirection: true), brush, false)
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
        .fillPreparedPathList(pathList.normalizedFill(rule == .EvenOdd ? Clipper.PolyFillType.EvenOdd : Clipper.PolyFillType.NonZero, byDirection: false), brush, true)
    }

    // Fills a list of paths under an explicitly named fill rule with a solid color.
    mtd fillPath(pathList: *LinePathList, color: Color, rule: PathFillRule)
    {
        .fillPath(pathList, Brush.createSolid(color), rule)
    }

    // `ruled` says the list was prepared for a fill rule rather than for the winding direction,
    // which decides how a lone contour that runs anticlockwise is read.
    private mtd fillPreparedPathList(pathList: *LinePathList, brush: Brush, ruled: bool)
    {
        fillRegions(pathList, &.sharedContours, &.sharedRegions)

        for region in .sharedRegions
        {
            let contours = .sharedContours.toSlice()[region.first until region.first + region.count]

            // The tessellator is fed the region's contours only when the region still has to be
            // triangulated. A page painted again has every one of them cached, and walking its
            // contours into a tessellator whose result would be discarded is most of what a
            // repeated fill would otherwise cost.
            let build = region.flush.triangles.vertices.isEmpty()
            if build
            {
                for contour in contours do
                    .tess.addPolyLine(contour.polygon)
            }

            .fillPathTriangulated(build ? &.tess : null, region.flush, pathList.minBounds, pathList.maxBounds, brush, contours, ruled)
        }
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

// Builds the tessellation a fill would build, without recording anything.
//
// A fill caches its triangulation inside the contours it fills, so the frame that first draws a
// shape pays for it and the frames after it do not. That is what makes drawing an unchanged
// document cheap — and what makes the first frame at a new scale expensive, because flattening
// the geometry finer replaces the contours every cached tessellation was keyed on. A consumer
// that knows ahead of the frame what it is about to draw, and at what scale — a document viewer
// that has just decoded a page, or one whose window has just been resized — can pay that here
// instead, and on whatever thread it likes: nothing below reads a painter, a renderer, or any
// state shared between them.
//
// The preparer owns the workspaces the build needs, so preparing a page's worth of shapes
// allocates once rather than once per shape. One preparer serves one thread, and the geometry it
// is given must not be drawn while it is preparing it.
//
// ```swag
// var preparer: FillPreparer
// for shape in page do
//     preparer.prepare(shape, scale, .NonZero)
// ```
#[Swag.Opaque]
public struct FillPreparer
{
    tess:       Poly2Tri.Tessellate
    directions: HashTable'(u64, Vector2)
    contours:   Array'(*LinePath)
    regions:    Array'FillRegion
}

public impl FillPreparer
{
    // Prepares what [[Pixel.Painter.fillPath]] under `rule` would build for `pathList`.
    //
    // `scale` is the number of device pixels one path unit covers, the way
    // [[Pixel.Painter.setFlattenScale]] reads it, and is quantized the same way: ask for the
    // scale the shape will be drawn at, and the frame that draws it finds everything cached.
    // Asking for less leaves the frame to flatten the geometry again; asking for more only costs
    // the extra segments.
    mtd prepare(pathList: *LinePathList, scale: f32, rule: PathFillRule, quality = PaintQuality.Normal)
    {
        pathList.flatten(quality, Painter.quantizeFlattenScale(scale))
        .prepareRegions(pathList.normalizedFill(rule == .EvenOdd ? Clipper.PolyFillType.EvenOdd : Clipper.PolyFillType.NonZero, byDirection: false), true)
    }

    // Prepares what the winding-direction [[Pixel.Painter.fillPath]] would build for `pathList`.
    mtd prepare(pathList: *LinePathList, scale: f32, quality = PaintQuality.Normal)
    {
        pathList.flatten(quality, Painter.quantizeFlattenScale(scale))
        .prepareRegions(pathList.normalizedFill(.NonZero, byDirection: true), false)
    }

    // Flattens a path for a draw at `scale`, without tessellating anything.
    //
    // A stroked path is turned into geometry by the frame that draws it, so there is no
    // tessellation to build for one; flattening it here still keeps the frame from doing it.
    mtd flatten(pathList: *LinePathList, scale: f32, quality = PaintQuality.Normal)
    {
        pathList.flatten(quality, Painter.quantizeFlattenScale(scale))
    }

    // Triangulates every region of an already flattened and normalized list.
    private mtd prepareRegions(pathList: *LinePathList, ruled: bool)
    {
        fillRegions(pathList, &.contours, &.regions)
        for region in .regions where region.flush.triangles.vertices.isEmpty()
        {
            let contours = .contours.toSlice()[region.first until region.first + region.count]
            for contour in contours do
                .tess.addPolyLine(contour.polygon)
            buildRegionTessellation(&.tess, &.directions, region.flush, contours, ruled)
        }
    }
}
