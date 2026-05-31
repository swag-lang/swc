using Core, Core.Math

public impl Painter
{
    // Emit a connected, mitered antialiasing fringe ring around a closed polygon
    // contour. Adjacent edges share their mitered inner/outer vertices, so corners
    // stay seamless (no per-edge wedges). The band is centered on the contour
    // (AAHalf inside / AAHalf outside).
    fileprivate mtd fillContourAA(polygon: *Polygon, color: Color)
    {
        let count = polygon.points.count - 1
        if count < 2 do
            return

        let argb = color.argb
        for i in count
        {
            let j      = (i + 1) % count
            let innerA = polygon.getPoint(i, -AAHalf)
            let outerA = polygon.getPoint(i, AAHalf)
            let innerB = polygon.getPoint(j, -AAHalf)
            let outerB = polygon.getPoint(j, AAHalf)
            .pushFringeQuad(innerA, outerA, innerB, outerB, argb)
        }
    }

    fileprivate mtd fillPath(t: *Poly2Tri.Tessellate, p: *LinePath, bvMin, bvMax: Vector2, brush: Brush)
    {
        .setTexture0(bvMin, bvMax, brush)
        .resetTextureFont()

        // Triangulation
        if p.triangles.triIndices.count == 0
        {
            t.triangulate()
            p.triangles = t.getResult()
            t.clear()
        }

        // Paint the solid interior on the true contour (the triangulation is cached,
        // so it must not be inset). The fringe is added separately as a centered band;
        // its inner half overlaps the solid, which is harmless for opaque fills (same
        // colour over same colour). Convex fills inset the solid to avoid the overlap
        // entirely; non-convex fills accept a faint rim on translucent colours.
        foreach i in p.triangles.triIndices
        {
            let tri = p.triangles.triangles[i]
            discard .pushTriangle(tri.points[0].v, tri.points[1].v, tri.points[2].v, brush.color)
        }

        if .curState.paintParams & .Antialiased do
            .fillContourAA(&p.polygon, brush.color)
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
        path.flatten(.curState.paintQuality)
        if Math.isZeroEpsilon(path.polygon.totalLen) do
            return

        let polygon = &path.polygon

        // Convex shape : faster
        if polygon.isConvex
        {
            .setTexture0(path.bvMin, path.bvMax, brush)
            .resetTextureFont()

            let count = path.polygon.points.count - 1

            // When antialiased, inset the solid by half a fringe so that the centered
            // fringe band (added afterwards) never overlaps the solid fill. This keeps
            // translucent fills clean and the silhouette at its true size.
            var so = 0'f32
            if .curState.paintParams & .Antialiased do
                so = -AAHalf

            // Convex shape : 1 triangle
            if count == 3
            {
                discard .pushTriangle(polygon.getPoint(0, so), polygon.getPoint(1, so), polygon.getPoint(2, so), brush.color)
            }

            // Convex shape : 2 triangles
            elif count == 4
            {
                let v0 = polygon.getPoint(0, so)
                let v1 = polygon.getPoint(1, so)
                let v2 = polygon.getPoint(2, so)
                let v3 = polygon.getPoint(3, so)
                discard .pushTriangle(v0, v1, v2, brush.color)
                discard .pushTriangle(v0, v2, v3, brush.color)
            }

            // Convex shape: add a triangle from the center of the shape to each pair of
            // vertices
            else
            {
                let center = Vector2{path.bvMin.x + (path.bvMax.x - path.bvMin.x) * 0.5, path.bvMin.y + (path.bvMax.y - path.bvMin.y) * 0.5}
                for i in count
                {
                    let v0 = polygon.getPoint(i, so)
                    let v1 = polygon.getPoint((i + 1) % count, so)
                    discard .pushTriangle(center, v0, v1, brush.color)
                }
            }

            if .curState.paintParams & .Antialiased do
                .fillContourAA(polygon, brush.color)
        }

        // Non convex shape: complex painting (triangulation)
        else
        {
            .sharedLinePathList.paths.add(path)
            .fillPath(&.sharedLinePathList, brush)
            .sharedLinePathList.paths.count = 0
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
        pathList.flatten(.curState.paintQuality)

        var flush: *LinePath

        // Everything in the cache ?
        var serial = 0
        var dirty  = false
        foreach p in pathList.paths
        {
            if (p.polygon.isClockwise or serial != p.serial) and flush
            {
                if !flush.triangles.triIndices.count
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
        if flush and !flush.triangles.triIndices.count do
            dirty = true

        serial = 0
        flush  = null

        foreach p in pathList.paths
        {
            if (p.polygon.isClockwise or serial != p.serial) and flush
            {
                serial = p.serial
                .fillPath(dirty ? &.tess : null, flush, pathList.bvMin, pathList.bvMax, brush)
                flush = null
            }

            if p.polygon.points.count >= 3
            {
                flush = p
                if dirty do
                    .tess.addPolyLine(p.polygon)
            }
        }

        if flush do
            .fillPath(dirty ? &.tess : null, flush, pathList.bvMin, pathList.bvMax, brush)
    }

    // Fill the polygon with the given color
    mtd fillPolygon(path: *LinePath, color: Color)
    {
        if color.a == 0 do
            return

        let brush = Brush.createSolid(color)
        .fillPolygon(path, brush)
    }

    // Fill the polygon with the given 'brush'
    mtd fillPolygon(path: *LinePath, brush: Brush)
    {
        if brush.color.a == 0 do
            return

        path.flatten(.curState.paintQuality)
        if path.polygon.isConvex
        {
            .fillPath(path, brush)
        }
        else
        {
            path.polygon.isClockwise = true
            let res = path.polygon.getClean()
            foreach p in res.paths do
                .fillPath(p, brush)
        }
    }

    // Fill the polygon with the given 'brush'
    mtd fillPolygon(points: [..] Math.Vector2, brush: Brush)
    {
        if @countof(points) < 3 do
            return

        var path: LinePath
        path.start(points[0].x, points[0].y)
        foreach pt in points where @index do
            path.lineTo(pt.x, pt.y)
        path.close()
        .fillPath(&path, brush)
    }
}
