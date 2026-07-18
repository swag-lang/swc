#global #[Swag.ExplicitNullability]
#global public
using Core, Core.Math

struct LinePathList
{
    paths:     Array'(#nonull *LinePath)
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
        for p, i in .paths
        {
            var ptr = Memory.new'LinePath()
            dref ptr  = dref p
            .paths[i] = ptr
        }
    }

    #[Swag.Inline]
    mtd count() => .paths.count

    // Remove all private line paths
    mtd clear()
    {
        for p in .paths do
            Memory.delete(p)
        .paths.clear()
    }

    // Returns a new path
    mtd newPath()->#nonull *LinePath
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
        for p in .paths
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

        for p in .paths
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

        var newList: LinePathList
        newList.bvMin = Vector2.Max
        newList.bvMax = Vector2.NegMax

        var serial = 0
        var i      = 0'u64
        while i < .paths.count
        {
            serial = .paths[i].serial

            var off: Clipper.Offset
            off.arcTolerance = toler * ClipperScaleCoords

            while i < .paths.count and .paths[i].serial == serial
            {
                .paths[i].polygon.addOffsetInputs(&off, joinType)
                i += 1
            }

            var res: Clipper.ClipperPaths
            off.execute(&res, cast(f64) (value * ClipperScaleCoords))

            for path in res
            {
                let np = newList.newPath()
                np.serial = serial
                np.polygon.storeClipperResult(path)
                np.polygon.setupGeneratedPath(np)
                newList.bvMin = Vector2.min(newList.bvMin, np.bvMin)
                newList.bvMax = Vector2.max(newList.bvMax, np.bvMax)
            }
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
        var newList: LinePathList
        newList.bvMin = Vector2.Max
        newList.bvMax = Vector2.NegMax

        var serial = 0
        var i      = 0'u64
        while i < .paths.count
        {
            serial = .paths[i].serial

            var trf: Clipper.Transform
            var hasClockwise = false
            while i < .paths.count and .paths[i].serial == serial
            {
                if .paths[i].polygon.isClockwise do
                    hasClockwise = true

                var path: Clipper.ClipperPath
                .paths[i].polygon.appendClipperPath(&path)
                trf.addPath(&path, .Subject)
                i += 1
            }

            trf.reverseOutput = !hasClockwise

            var res: Clipper.ClipperPaths
            trf.execute(.Union, &res, .NonZero, .NonZero)

            for path in res
            {
                let np = newList.newPath()
                np.serial = serial
                np.polygon.storeClipperResult(path)
                np.polygon.setupGeneratedPath(np)
                newList.bvMin = Vector2.min(newList.bvMin, np.bvMin)
                newList.bvMax = Vector2.max(newList.bvMax, np.bvMax)
            }
        }

        .clear()
        .paths = #move newList.paths
        .bvMin = newList.bvMin
        .bvMax = newList.bvMax
    }
}
