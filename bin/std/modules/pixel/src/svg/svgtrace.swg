#global public
#global namespace Svg

using Core, Core.Math

// Configures [[Svg.trace]].
struct TraceOptions
{
    public
    {
        // Contour simplification tolerance, in source pixels. Larger values produce
        // lighter documents; smaller values follow the pixel edges more closely.
        tolerance: f32 = 0.6

        // Alpha level treated as the shape boundary. The traced contour passes through
        // the sub-pixel position where the antialiased alpha crosses this value.
        threshold: u8 = 127
    }
}

// Traces a flat-color raster image into a vector document.
//
// Pixels are grouped by color; each group's coverage is contour-traced with
// sub-pixel precision on the antialiased alpha boundary, simplified, and written
// as one filled shape per color, in back-to-front coverage order. The result is
// faithful for the flat-color art this is meant for — icon glyphs, UI masks — and
// approximate for photographs, which have no flat regions to trace.
//
// ## Example
//
// ```swag
// let image = try Image.load("icon.png")
// let doc   = Svg.trace(&image)
// try doc.save("icon.svg")
// ```
func trace(image: const *Image, options: TraceOptions = {})->Document
{
    Debug.assert(image != null and image.isValid())

    var result: retval = Document.create(image.width, image.height)

    let w = image.width
    let h = image.height

    // Sample helpers over the source, BGRA8 or RGBA8.
    let bpp     = cast(s32) image.bytesPerPixel
    let rOffset = image.pixelFormat == .RGBA8 or image.pixelFormat == .RGB8 ? 0 : 2
    let bOffset = 2 - rOffset

    func sample(image: const *Image, bpp, rOffset, bOffset: s32, x, y: s32)->{ color: Color, alpha: u8 }
    {
        var result: retval
        if x < 0 or y < 0 or x >= image.width or y >= image.height do
            return result

        let idx = (cast(u64) y * cast(u64) image.width + cast(u64) x) * cast(u64) bpp
        let ptr = image.pixels.buffer! + idx
        let a   = bpp == 4 ? ptr[3] : 255'u8
        result.color = Color.fromArgb(255, ptr[rOffset], ptr[1], ptr[bOffset])
        result.alpha = a
        return result
    }

    // Collect the distinct colors of sufficiently opaque pixels, most frequent
    // first so large fills are written before the details drawn over them.
    var colorCount: HashTable'(u32, u64)
    for y in h
    {
        for x in w
        {
            let {color, alpha} = sample(image, bpp, rOffset, bOffset, x, y)
            if alpha <= options.threshold do
                continue
            let key  = color.argb & 0x00FFFFFF
            let here = colorCount.tryFind(key)
            if here do
                here.value += 1
            else do
                colorCount.add(key, 1)
        }
    }

    var colors: Array'{ key: u32, count: u64 }
    for key, count in colorCount do
        colors.add({key, count})
    colors.sort(func||(a, b) => b.count <=> a.count)

    // Trace each color class independently.
    for entry in colors
    {
        var paths = traceClass(image, bpp, rOffset, bOffset, entry.key, options)
        if paths.paths.isEmpty() do
            continue

        // Average the class alpha so a uniformly translucent layer keeps its opacity.
        var alphaSum, alphaCount: u64
        for y in h
        {
            for x in w
            {
                let {color, alpha} = sample(image, bpp, rOffset, bOffset, x, y)
                if alpha > options.threshold and (color.argb & 0x00FFFFFF) == entry.key
                {
                    alphaSum   += alpha
                    alphaCount += 1
                }
            }
        }

        var color = Color.fromArgb(entry.key | 0xFF000000)
        if alphaCount do
            color.a = cast(u8) (alphaSum / alphaCount)
        result.addPath(paths, color, .NonZero)
    }

    return result
}

// Membership of a pixel in the traced color class, as a coverage value: the class
// alpha where the pixel matches, zero where it belongs to another color, and the
// inverted neighborhood for the outer transparent boundary.
private func coverage(image: const *Image, bpp, rOffset, bOffset: s32, key: u32, threshold: u8, x, y: s32)->f32
{
    if x < 0 or y < 0 or x >= image.width or y >= image.height do
        return 0

    let idx = (cast(u64) y * cast(u64) image.width + cast(u64) x) * cast(u64) bpp
    let ptr = image.pixels.buffer! + idx
    let a   = bpp == 4 ? ptr[3] : 255'u8
    if a == 0 do
        return 0

    let pixKey = (cast(u32) ptr[rOffset] << 16) | (cast(u32) ptr[1] << 8) | cast(u32) ptr[bOffset]
    if a > threshold and pixKey != key do
        return 0

    // Matching or antialiased-boundary pixel: its alpha is the class coverage.
    return cast(f32) a / 255.0
}

// Traces every contour of one color class with marching squares.
//
// Cell corners sit on pixel centers; edge crossings interpolate the coverage so
// the contour follows the antialiased boundary with sub-pixel precision.
private func traceClass(image: const *Image, bpp, rOffset, bOffset: s32, key: u32, options: TraceOptions)->LinePathList
{
    var result: retval

    let w   = image.width
    let h   = image.height
    let thr = 0.5'f32

    // Corner coverage grid, one sample per pixel center, padded by one so outer
    // boundaries close.
    let gw = w + 2
    let gh = h + 2
    var grid: Array'f32
    grid.resize(cast(u64) gw * cast(u64) gh)
    for y in gh
    {
        for x in gw do
            grid[cast(u64) y * cast(u64) gw + cast(u64) x] = coverage(image, bpp, rOffset, bOffset, key, options.threshold, x - 1, y - 1)
    }

    func at(grid: *Array'f32, gw: s32, x, y: s32)->f32 => (dref grid)[cast(u64) y * cast(u64) gw + cast(u64) x]

    // One flag per cell edge crossing, so each contour is walked exactly once.
    // Index: cell (x, y) with 2 horizontal-crossing slots (top edge) per cell.
    var visited: Array'bool
    visited.resize(cast(u64) gw * cast(u64) gh)

    // Walk the segment grid: standard marching squares with linear interpolation.
    // For each cell whose top edge crosses the contour and was not consumed yet,
    // follow the boundary until it returns to the start.
    for cy in gh - 1
    {
        for cx in gw - 1
        {
            let a = at(&grid, gw, cx, cy)
            let b = at(&grid, gw, cx + 1, cy)
            if (a >= thr) == (b >= thr) do
                continue
            if visited[cast(u64) cy * cast(u64) gw + cast(u64) cx] do
                continue

            // Trace one closed contour starting at this top-edge crossing.
            visited[cast(u64) cy * cast(u64) gw + cast(u64) cx] = true
            var path: #null *LinePath

            var x      = cx
            var y      = cy
            var entry  = 0     // 0 top, 1 right, 2 bottom, 3 left: edge we entered through.
            let startX = cx
            let startY = cy
            var guard  = cast(u64) gw * cast(u64) gh * 4

            while guard
            {
                guard -= 1

                let c00 = at(&grid, gw, x, y)
                let c10 = at(&grid, gw, x + 1, y)
                let c01 = at(&grid, gw, x, y + 1)
                let c11 = at(&grid, gw, x + 1, y + 1)

                var config = 0
                if c00 >= thr do
                    config |= 1
                if c10 >= thr do
                    config |= 2
                if c11 >= thr do
                    config |= 4
                if c01 >= thr do
                    config |= 8

                if config == 0 or config == 15 do
                    break

                // Resolve the exit edge for the entry edge on this configuration.
                // Saddles (5, 10) choose the turn that keeps the filled area on the
                // same side, disambiguated with the cell average.
                var exitEdge = -1
                switch config
                {
                case 1:
                    exitEdge = entry == 0 ? 3 : 0

                case 2:
                    exitEdge = entry == 0 ? 1 : 0

                case 3:
                    exitEdge = entry == 3 ? 1 : 3

                case 4:
                    exitEdge = entry == 1 ? 2 : 1

                case 6:
                    exitEdge = entry == 0 ? 2 : 0

                case 7:
                    exitEdge = entry == 3 ? 2 : 3

                case 8:
                    exitEdge = entry == 2 ? 3 : 2

                case 9:
                    exitEdge = entry == 0 ? 2 : 0

                case 11:
                    exitEdge = entry == 1 ? 2 : 1

                case 12:
                    exitEdge = entry == 3 ? 1 : 3

                case 13:
                    exitEdge = entry == 0 ? 1 : 0

                case 14:
                    exitEdge = entry == 0 ? 3 : 0

                case 5:
                    let center = (c00 + c10 + c01 + c11) * 0.25
                    if entry == 0 do
                        exitEdge = center >= thr ? 1 : 3
                    elif entry == 2 do
                        exitEdge = center >= thr ? 3 : 1
                    elif entry == 1 do
                        exitEdge = center >= thr ? 0 : 2
                    else do
                        exitEdge = center >= thr ? 2 : 0

                case 10:
                    let center = (c00 + c10 + c01 + c11) * 0.25
                    if entry == 0 do
                        exitEdge = center >= thr ? 3 : 1
                    elif entry == 2 do
                        exitEdge = center >= thr ? 1 : 3
                    elif entry == 3 do
                        exitEdge = center >= thr ? 0 : 2
                    else do
                        exitEdge = center >= thr ? 2 : 0
                }

                if exitEdge < 0 do
                    break

                // Sub-pixel crossing point on the exit edge. Grid corner (x, y) is
                // source pixel center (x - 1 + 0.5, y - 1 + 0.5).
                func crossing(va, vb: f32, thr: f32)->f32
                {
                    let d = vb - va
                    if Math.abs(d) < 0.0001 do
                        return 0.5
                    return Math.saturate((thr - va) / d)
                }

                var px, py: f32
                switch exitEdge
                {
                case 0:
                    px = x - 0.5 + crossing(c00, c10, thr)
                    py = y - 0.5

                case 1:
                    px = x + 0.5
                    py = y - 0.5 + crossing(c10, c11, thr)

                case 2:
                    px = x - 0.5 + crossing(c01, c11, thr)
                    py = y + 0.5

                case 3:
                    px = x - 0.5
                    py = y - 0.5 + crossing(c00, c01, thr)
                }

                if !path
                {
                    path = result.newPath()
                    path!.start(px, py)
                }
                else do
                    path!.lineTo(px, py)

                // Mark consumed top-edge crossings so no contour is traced twice.
                if exitEdge == 0 do
                    visited[cast(u64) y * cast(u64) gw + cast(u64) x] = true
                elif exitEdge == 2 do
                    visited[cast(u64) (y + 1) * cast(u64) gw + cast(u64) x] = true

                // Step into the neighbouring cell.
                switch exitEdge
                {
                case 0:
                    y     -= 1
                    entry = 2

                case 1:
                    x     += 1
                    entry = 3

                case 2:
                    y     += 1
                    entry = 0

                case 3:
                    x     -= 1
                    entry = 1
                }

                if x == startX and y == startY and entry == 0 do
                    break

                // A contour reaching the padded border must not walk off the grid.
                if x < 0 or y < 0 or x >= gw - 1 or y >= gh - 1 do
                    break
            }

            if path
            {
                let p = path!
                simplifyPath(p, options.tolerance)
                p.close()
            }
        }
    }

    return result
}

// Ramer-Douglas-Peucker simplification of an open polyline, in place.
private func simplifyPath(path: *LinePath, tolerance: f32)
{
    if tolerance <= 0 do
        return

    // Collect the raw points.
    var points: Array'Vector2
    for elem in path.elements do
        points.add(elem.position)
    if points.count < 3 do
        return

    var keep: Array'bool
    keep.resize(points.count)
    keep[0], keep[points.count - 1] = true

    // Iterative stack instead of recursion.
    var stack: Array'{ first: u64, last: u64 }
    stack.add({0, points.count - 1})

    while stack.count
    {
        let {first, last} = stack.popBack()
        if last <= first + 1 do
            continue

        let a      = points[first]
        let b      = points[last]
        let ab     = b - a
        let abLen2 = Math.max(ab.dot(ab), 0.000001)

        var far     = first
        var farDist = 0.0'f32
        for var i = first + 1; i < last; i += 1
        {
            let ap = points[i] - a
            let t  = Math.saturate(ap.dot(ab) / abLen2)
            let d  = ap - ab * t
            let d2 = d.dot(d)
            if d2 > farDist
            {
                farDist = d2
                far     = i
            }
        }

        if farDist > tolerance * tolerance
        {
            keep[far] = true
            stack.add({first, far})
            stack.add({far, last})
        }
    }

    // Rebuild the path with the kept points.
    var kept: Array'Vector2
    for i in points.count where keep[i] do
        kept.add(points[i])

    path.clear()
    path.start(kept[0].x, kept[0].y)
    for var i = 1'u64; i < kept.count; i += 1 do
        path.lineTo(kept[i].x, kept[i].y)
}
