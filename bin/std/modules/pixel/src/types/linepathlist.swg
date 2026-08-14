#global public

using Core, Core.Math

// Owns an ordered collection of heap-allocated paths and their combined bounds.
//
// Copies are deep: each path is duplicated and remains independently mutable.
struct LinePathList
{
    internal paths: Array'(*LinePath)     // Owned path pointers.

    // Combined bounds of the paths, derived when the list is flattened.
    public readonly
    {
        minBounds: Vector2     // Minimum combined bound after flattening.
        maxBounds: Vector2     // Maximum combined bound after flattening.
    }
}

impl LinePathList
{
    // Establishes the combined bounds of the list.
    //
    // The operations that build a list from an existing shape already know its bounds, so they
    // carry them over instead of walking every path again.
    internal mtd setBounds(min, max: Vector2)
    {
        .minBounds = min
        .maxBounds = max
    }

    // Releases every owned path when the list leaves scope.
    mtd opDrop()
    {
        .clear()
    }

    // Deep-copies every owned path after copying the list.
    mtd opPostCopy()
    {
        for p, i in .paths
        {
            var ptr = Memory.new'LinePath()
            ptr[]     = p[]
            .paths[i] = ptr
        }
    }

    // Returns the number of owned paths.
    #[Swag.Inline]
    mtd count() => .paths.count

    // Returns a borrowed read-only view of the owned path pointers.
    //
    // The view is invalidated when the list is cleared, offset, cleaned, copied,
    // or destroyed.
    mtd const toSlice()->const [..] *LinePath => .paths.toSlice()

    // Releases and removes all owned paths.
    mtd clear()
    {
        for p in .paths do
            Memory.delete(p)
        .paths.clear()
        .setBounds({}, {})
    }

    // Allocates, owns, and returns a new empty path.
    mtd newPath()->*LinePath
    {
        let ptr = Memory.new'LinePath()
        .paths.add(ptr)
        return ptr
    }

    // Flattens all paths at `quality` and recomputes combined bounds.
    mtd flatten(quality: PaintQuality = .Normal)
    {
        if .paths.isEmpty()
        {
            .setBounds({}, {})
            return
        }

        .minBounds = Vector2.Max
        .maxBounds = Vector2.NegMax
        for p in .paths
        {
            p.flatten(quality)
            .minBounds = Vector2.min(.minBounds, p.minBounds)
            .maxBounds = Vector2.max(.maxBounds, p.maxBounds)
        }
    }

    // Offsets every already-flattened polygon using its winding direction.
    mtd offset(value: f32)
    {
        if Math.isZeroEpsilon(value) do
            return

        for p, i in .paths
        {
            let v = p.polygon.isClockwise ? value : -value
            p.polygon.offset(v)
            p.minBounds = p.polygon.minBounds
            p.maxBounds = p.polygon.maxBounds
            if i == 0 do
                .setBounds(p.minBounds, p.maxBounds)
            else do
                .setBounds(Vector2.min(.minBounds, p.minBounds), Vector2.max(.maxBounds, p.maxBounds))
        }
    }

    // Rebuilds every already-flattened path with a quality offset.
    //
    // `toler` controls round-join approximation in pixels.
    mtd offset(value: f32, joinStyle: JoinStyle, toler: f32 = 0.5)
    {
        if Math.isZeroEpsilon(value) do
            return

        var joinType = Clipper.JoinType.Square
        switch joinStyle
        {
        case .Round: joinType = .Round
        case .Bevel: joinType = .Square
        case .Miter: joinType = .Miter
        }

        var newList: LinePathList
        newList.minBounds = Vector2.Max
        newList.maxBounds = Vector2.NegMax

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
                newList.minBounds = Vector2.min(newList.minBounds, np.minBounds)
                newList.maxBounds = Vector2.max(newList.maxBounds, np.maxBounds)
            }
        }

        .clear()
        .paths     = #move newList.paths
        .minBounds = newList.minBounds
        .maxBounds = newList.maxBounds
    }

    // Unions and normalizes groups of already-flattened paths.
    mtd clean()
    {
        var newList: LinePathList
        newList.minBounds = Vector2.Max
        newList.maxBounds = Vector2.NegMax

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
                newList.minBounds = Vector2.min(newList.minBounds, np.minBounds)
                newList.maxBounds = Vector2.max(newList.maxBounds, np.maxBounds)
            }
        }

        .clear()
        .paths = #move newList.paths

        // An empty result has no bounds. Reporting the sentinels the loop starts from, or the
        // bounds of the shape that was cleaned away, would describe geometry that is gone.
        if .paths.isEmpty() do
            .setBounds({}, {})
        else do
            .setBounds(newList.minBounds, newList.maxBounds)
    }
}
