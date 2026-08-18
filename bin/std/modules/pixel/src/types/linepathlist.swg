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

    // Fill-normalization cache (see [[Pixel.LinePathList.normalizedFill]]): the verdict and,
    // when normalizing was needed, the owned normalized copy. Keyed by the revision of every
    // contour, so any geometry change rebuilds it and an unchanged list never normalizes twice.
    internal
    {
        fillCache:            #null *LinePathList     // Owned normalized copy, when one was needed.
        fillCacheStamps:      Array'u64                // Contour revisions the cache was built from.
        fillCacheRule:        Clipper.PolyFillType = NonZero
        fillCacheDirect:      bool                     // The source can be filled as it is.
        fillCacheByDirection: bool                     // The cache serves the winding-direction fill.
        fillCacheValid:       bool
    }
}

private func contourPointCount(polygon: const *Polygon)->u64
{
    let count = polygon.points.count
    if count > 1 and polygon.points[0].isEqualEpsilon(polygon.points[count - 1]) do
        return count - 1
    return count
}

private func contoursIntersect(a, b: const *Polygon)->bool
{
    if a.maxBounds.x < b.minBounds.x or b.maxBounds.x < a.minBounds.x or a.maxBounds.y < b.minBounds.y or b.maxBounds.y < a.minBounds.y do
        return false

    let countA = contourPointCount(a)
    let countB = contourPointCount(b)
    if countA < 2 or countB < 2 do
        return false

    for i in countA
    {
        let a0 = a.points[i]
        let a1 = a.points[(i + 1) % countA]
        for j in countB
        {
            let b0 = b.points[j]
            let b1 = b.points[(j + 1) % countB]
            if Geometry.intersectSegments(a0, a1, b0, b1, 0.01).intersects do
                return true
        }
    }

    return false
}

private func pathListNeedsCleaning(pathList: const *LinePathList)->bool
{
    for p in pathList.paths where !p.polygon.isSimple do
        return true

    for i in pathList.paths.count
    {
        var j = i + 1
        while j < pathList.paths.count
        {
            defer j += 1
            if contoursIntersect(&pathList.paths[i].polygon, &pathList.paths[j].polygon) do
                return true
        }
    }

    return false
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
    //
    // The fill cache stays with the source: its pointer was copied raw, so it is detached
    // here rather than dropped, and the copy rebuilds its own on first use.
    mtd opPostCopy()
    {
        for p, i in .paths
        {
            var ptr = Memory.new'LinePath()
            ptr[]     = p[]
            .paths[i] = ptr
        }

        .fillCache = null
        .fillCacheStamps.clear()
        .fillCacheValid = false
    }

    // Drops the cached fill normalization; the next fill rebuilds it.
    private mtd invalidateFillCache()
    {
        if .fillCache
        {
            Memory.delete(.fillCache!)
            .fillCache = null
        }

        .fillCacheStamps.clear()
        .fillCacheValid = false
    }

    // Returns the number of owned paths.
    #[Swag.Inline]
    mtd const count() => .paths.count

    // Returns a borrowed read-only view of the owned path pointers.
    //
    // The view is invalidated when the list is cleared, offset, cleaned, copied,
    // or destroyed.
    mtd const toSlice()->const [..] *LinePath => .paths.toSlice()

    // Returns the rectangle enclosing every point that defines the owned paths.
    //
    // This is the union of each path's [[Pixel.LinePath.controlBounds]], and shares its
    // properties: it needs no flattening, it can be wider than the ink, and it is never
    // narrower. An empty list answers an empty rectangle.
    mtd const controlBounds()->Math.Rectangle
    {
        var result: retval
        for path, index in .paths
        {
            let bounds = path.controlBounds()
            if !index do
                result = bounds
            else do
                result.expandToInclude(bounds)
        }

        return result
    }

    // Releases and removes all owned paths.
    mtd clear()
    {
        .invalidateFillCache()
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
    //
    // `scale` is the number of device pixels one path unit covers when the result is drawn;
    // see [[Pixel.LinePath.flatten]].
    mtd flatten(quality: PaintQuality = .Normal, scale = 1.0'f32)
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
            p.flatten(quality, scale)
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
            p.touchContour()
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

    // Moves the paths of `solved` over, each outer contour followed by its own holes.
    //
    // Emptying the source is what keeps the paths owned exactly once: they are heap values
    // this type deletes, so they are handed over rather than copied.
    private mtd appendGroupedByContainment(solved: *LinePathList)
    {
        var claimed: Array'bool
        claimed.resize(solved.paths.count)

        for outer in solved.paths where outer.polygon.isClockwise
        {
            .paths.add(outer)
            for hole, index in solved.paths where !hole.polygon.isClockwise and !claimed[index]
            {
                // A hole lies wholly inside its outer, so the cheap bounds test settles
                // every pair but the few that share a region, and one point decides those:
                // the contours of a boolean result never cross.
                if hole.minBounds.x < outer.minBounds.x or hole.maxBounds.x > outer.maxBounds.x do
                    continue
                if hole.minBounds.y < outer.minBounds.y or hole.maxBounds.y > outer.maxBounds.y do
                    continue
                if !outer.polygon.points.count or !hole.polygon.points.count do
                    continue
                if !outer.polygon.contains(hole.polygon.pointAt(0)[]) do
                    continue

                claimed[index] = true
                .paths.add(hole)
            }
        }

        // A hole no outer claims encloses nothing, and the fill would paint it as a shape
        // of its own. Dropping it is what keeps the result the region the rule defined.
        for path, index in solved.paths where !path.polygon.isClockwise and !claimed[index] do
            Memory.delete(path)

        solved.paths.clear()
    }

    // Unions and normalizes groups of already-flattened paths.
    //
    // `rule` decides which regions of a self-overlapping or multi-contour group count as
    // interior. The default treats a nonzero winding count as filled, which is what the
    // clockwise-outer, anticlockwise-hole convention of this type expresses; pass
    // `EvenOdd` for geometry authored under the alternating rule, where two overlapping
    // contours of the same direction cancel instead of merging.
    mtd clean(rule = Clipper.PolyFillType.NonZero)
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
            while i < .paths.count and .paths[i].serial == serial
            {
                var path: Clipper.ClipperPath
                .paths[i].polygon.appendClipperPath(&path)
                trf.addPath(&path, .Subject)
                i += 1
            }

            // Normalizing is what this is for, so the result always comes back with its
            // outer contours clockwise and its holes anticlockwise — the arrangement every
            // consumer of a cleaned list reads. Carrying the input's own orientation over
            // instead would hand back a shape whose outer ring reads as a hole whenever the
            // geometry happened to be wound the other way, which is how the counter of a
            // letter ends up filled in.
            var res: Clipper.ClipperPaths
            trf.execute(.Union, &res, rule, rule)

            var solved: LinePathList
            for path in res
            {
                let np = solved.newPath()
                np.serial = serial
                np.polygon.storeClipperResult(path)
                np.polygon.setupGeneratedPath(np)
            }

            // The boolean result names the regions but not the order they belong in. A
            // consumer reads a shape as one outer contour followed by the holes inside it,
            // so a run of several shapes — every letter of an outlined word, say — has to be
            // regrouped: left in the order the solver happened to emit, one letter's counter
            // is read as a hole of a different letter, or of nothing at all.
            newList.appendGroupedByContainment(&solved)
        }

        .clear()
        .paths = #move newList.paths

        // An empty result has no bounds. Reporting the bounds of the shape that was cleaned
        // away would describe geometry that is gone.
        if .paths.isEmpty()
        {
            .setBounds({}, {})
            return
        }

        var minimum = Vector2.Max
        var maximum = Vector2.NegMax
        for path in .paths
        {
            minimum = Vector2.min(minimum, path.minBounds)
            maximum = Vector2.max(maximum, path.maxBounds)
        }

        .setBounds(minimum, maximum)
    }

    // Reports whether the fill cache still describes the current contours.
    private mtd const fillCacheMatches(rule: Clipper.PolyFillType, byDirection: bool)->bool
    {
        if !.fillCacheValid or .fillCacheRule != rule or .fillCacheByDirection != byDirection do
            return false
        if .fillCacheStamps.count != .paths.count do
            return false
        for p, i in .paths where .fillCacheStamps[i] != p.revision do
            return false
        return true
    }

    // Returns the geometry a fill can triangulate directly under `rule`, normalizing at most
    // once per geometry change.
    //
    // Deciding whether a list needs normalizing walks every contour pair, and normalizing
    // deep-copies the list through a boolean solver — both far too expensive to repeat for a
    // list that has not changed, which is every frame of a viewer painting a static document.
    // The verdict and the normalized copy are therefore cached against the revision of every
    // contour: an unchanged list answers immediately, and the copy keeps its own fill
    // tessellations alive from one fill to the next.
    //
    // `byDirection` selects the winding-direction convention of the plain fill, where a list
    // whose simple contours already express outers and holes is filled as it is; otherwise the
    // region is defined by `rule` over the winding count, and only a single simple contour
    // skips normalization. The list must be flattened first.
    internal mtd normalizedFill(rule: Clipper.PolyFillType, byDirection: bool)->*LinePathList
    {
        if .fillCacheMatches(rule, byDirection) do
            return .fillCacheDirect ? me : .fillCache!

        .invalidateFillCache()

        var direct = false
        if byDirection do
            direct = !pathListNeedsCleaning(me)
        else do
            direct = .paths.count < 2 and (.paths.isEmpty() or .paths[0].polygon.isSimple)

        if !direct
        {
            let cache = Memory.new'LinePathList()
            cache[] = me[]
            cache.clean(rule)
            .fillCache = cache
        }

        .fillCacheStamps.reserve(.paths.count)
        for p in .paths do
            .fillCacheStamps.add(p.revision)
        .fillCacheRule        = rule
        .fillCacheDirect      = direct
        .fillCacheByDirection = byDirection
        .fillCacheValid       = true
        return direct ? me : .fillCache!
    }
}
