#global public
using Core, Core.Math

struct LinePathList
{
    paths:     Array'(*LinePath)
    bvMin:     Vector2
    bvMax:     Vector2
}

impl LinePathList
{
    mtd opDrop()
    {
        .clear()
    }

    mtd opPostCopy()
    {
        foreach p, i in .paths
        {
            var ptr = Memory.new'LinePath()
            dref ptr  = dref p
            .paths[i] = ptr
        }
    }

    #[Swag.Inline]
    mtd count() => .paths.count

    // Remove all fileprivate line paths
    mtd clear()
    {
        foreach p in .paths do
            Memory.delete(p)
        .paths.clear()
    }

    // Returns a new path
    mtd newPath()->*LinePath
    {
        let ptr = Memory.new'LinePath()
        .paths.add(ptr)
        return ptr
    }

    // Flatten all paths
    mtd flatten(quality: PaintQuality)
    {
        // Flatten all path, and compute BV
        .bvMin = Vector2.Max
        .bvMax = Vector2.NegMax
        foreach p in .paths
        {
            p.flatten(quality)
            .bvMin = Vector2.min(.bvMin, p.bvMin)
            .bvMax = Vector2.max(.bvMax, p.bvMax)
        }
    }

    // Call fast offset on all paths
    // They must before be flattened
    mtd offset(value: f32)
    {
        if Math.isZeroEpsilon(value) do
            return

        foreach p in .paths
        {
            let v = p.polygon.isClockwise ? value : -value
            p.polygon.offset(v)
        }
    }

    // Call quality offset on all paths
    // They must before be flattened
    mtd offset(value: f32, joinStyle: JoinStyle, toler: f32 = 0.5)
    {
        if Math.isZeroEpsilon(value) do
            return

        var joinType = Clipper.JoinType.Square
        switch joinStyle
        {
        case Round:
            joinType = .Round
        case Bevel:
            joinType = .Square
        case Miter:
            joinType = .Miter
        }

        var off: Clipper.Offset
        off.arcTolerance = toler * ClipperScaleCoords
        foreach p in .paths do
            p.polygon.addOffsetInputs(&off, joinType)

        var res: Clipper.ClipperPaths
        off.execute(&res, cast(f64) (value * ClipperScaleCoords))

        var newList: LinePathList
        newList.bvMin = Vector2.Max
        newList.bvMax = Vector2.NegMax
        foreach path in res
        {
            let np = newList.newPath()
            np.polygon.storeClipperResult(path)
            np.polygon.setupGeneratedPath(np)
            newList.bvMin = Vector2.min(newList.bvMin, np.bvMin)
            newList.bvMax = Vector2.max(newList.bvMax, np.bvMax)
        }

        .clear()
        .paths = #move newList.paths
        .bvMin = newList.bvMin
        .bvMax = newList.bvMax
    }

    // Clean all paths
    // They must before be flattened
    mtd clean()
    {
        var trf: Clipper.Transform
        foreach p in .paths
        {
            if p.polygon.isClockwise
            {
                trf.reverseOutput = false
                break
            }

            trf.reverseOutput = true
        }

        foreach p in .paths
        {
            var path: Clipper.ClipperPath
            p.polygon.appendClipperPath(&path)
            trf.addPath(&path, .Subject)
        }

        var res: Clipper.ClipperPaths
        trf.execute(.Union, &res, .NonZero, .NonZero)

        var newList: LinePathList
        newList.bvMin = Vector2.Max
        newList.bvMax = Vector2.NegMax
        foreach path in res
        {
            let np = newList.newPath()
            np.polygon.storeClipperResult(path)
            np.polygon.setupGeneratedPath(np)
            newList.bvMin = Vector2.min(newList.bvMin, np.bvMin)
            newList.bvMax = Vector2.max(newList.bvMax, np.bvMax)
        }

        .clear()
        .paths = #move newList.paths
        .bvMin = newList.bvMin
        .bvMax = newList.bvMax
    }
}
