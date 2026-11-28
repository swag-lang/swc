#global public
#global namespace Svg

using Core, Core.Math

// Configures [[Pixel.Svg.trace]].
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

private struct TraceBounds
{
    left, top:     s32 = Swag.S32.Max
    right, bottom: s32 = -1
}

private impl TraceBounds
{
    mtd include(x, y: s32)
    {
        .left   = Math.min(.left, x)
        .top    = Math.min(.top, y)
        .right  = Math.max(.right, x)
        .bottom = Math.max(.bottom, y)
    }

    mtd const merged(other: TraceBounds)->TraceBounds
    {
        return {
            Math.min(.left, other.left), Math.min(.top, other.top),
            Math.max(.right, other.right), Math.max(.bottom, other.bottom),
        }
    }
}

private struct TraceColorStats
{
    count, alphaSum: u64
    bounds:          TraceBounds
}

// Traces a flat-color raster image into a vector document.
//
// Pixels are grouped by color; each group's coverage is contour-traced with
// sub-pixel precision on the antialiased alpha boundary, simplified, and written
// as one filled shape per color, in back-to-front coverage order. The result is
// faithful for the flat-color art this is meant for — icon glyphs, UI masks — and
// approximate for photographs, which have no flat regions to trace. Sampling uses
// the image's logical top-left pixels and straight-alpha colors, regardless of its
// packed format or stored alpha association.
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
    Swag.assert(image != null and image.isValid())

    var result: #returntype = Document.create(image.width, image.height)

    if options.threshold == Swag.U8.Max
    {
        return result
    }

    var colorStats: HashTable!{u32, TraceColorStats}
    var sharedBounds: TraceBounds
    for y in image.height
    {
        for x in image.width
        {
            let color = image.pixelColor(x, y)
            let alpha = color.a
            if alpha <= options.threshold
            {
                // Coverage at or below the color threshold is shared by every class.
                // Only alpha at or above half can enlarge the marching-squares grid.
                if alpha >= 128
                {
                    sharedBounds.include(x, y)
                }

                continue
            }

            let entry = colorStats.findOrAdd(color.argb & 0x00FFFFFF)
            entry.value.count    += 1
            entry.value.alphaSum += alpha
            if alpha >= 128
            {
                entry.value.bounds.include(x, y)
            }
        }
    }

    // Trace each color from most to least frequent, painting details over large fills.
    var colors: Array!{{ key: u32, stats: TraceColorStats }}
    for key, stats in colorStats
    {
        colors.add({key, stats})
    }

    colors.sort(func||(a, b) => b.stats.count <=> a.stats.count)
    for entry in colors
    {
        let bounds = entry.stats.bounds.merged(sharedBounds)
        var paths  = traceClass(image, entry.key, options, bounds)
        if paths.paths.isEmpty()
        {
            continue
        }

        // Average the class alpha so a uniformly translucent layer keeps its opacity.
        var color = Color.fromArgb(entry.key | 0xFF000000)
        color.a = cast(u8, (entry.stats.alphaSum / entry.stats.count))
        result.addPath(paths, color, .NonZero)
    }

    return result
}

// Membership of a pixel in the traced color class, as a coverage value: the class
// alpha where the pixel matches, zero where it belongs to another color, and the
// inverted neighborhood for the outer transparent boundary.
private func coverage(image: const *Image, key: u32, threshold: u8, x, y: s32)->f32
{
    if x < 0 or y < 0 or x >= image.width or y >= image.height
    {
        return 0
    }

    let color = image.pixelColor(x, y)
    let a     = color.a
    if a == 0
    {
        return 0
    }

    let pixKey = color.argb & 0x00FFFFFF
    if a > threshold and pixKey != key
    {
        return 0
    }

    // Matching or antialiased-boundary pixel: its alpha is the class coverage.
    return cast(f32, a) / 255.0
}

// Traces every contour of one color class with marching squares.
//
// Cell corners sit on pixel centers; edge crossings interpolate the coverage so
// the contour follows the antialiased boundary with sub-pixel precision.
private func traceClass(image: const *Image, key: u32, options: TraceOptions, bounds: TraceBounds)->LinePathList
{
    var result: #returntype
    if bounds.left > bounds.right
    {
        return result
    }

    let thr = 0.5_f32

    // Keep one sample beyond each side to close contours and interpolate coverage
    // at the edge of the occupied pixels, including closed edges at the image border.
    let gw = bounds.right - bounds.left + 3
    let gh = bounds.bottom - bounds.top + 3
    var grid: Array!{f32}
    grid.resize(cast(u64, gw) * cast(u64, gh))
    for y in gh
    {
        for x in gw
        {
            let value = coverage(image, key, options.threshold, x + bounds.left - 1, y + bounds.top - 1)
            grid[cast(u64, y) * cast(u64, gw) + cast(u64, x)] = value
        }
    }

    func at(grid: *Array!{f32}, gw: s32, x, y: s32)->f32 => grid[][cast(u64, y) * cast(u64, gw) + cast(u64, x)]

    // One flag per cell edge crossing, so each contour is walked exactly once.
    // Index: cell (x, y) with 2 horizontal-crossing slots (top edge) per cell.
    var visited: Array!{bool}
    visited.resize(cast(u64, gw) * cast(u64, gh))

    // Walk the segment grid: standard marching squares with linear interpolation.
    // For each cell whose top edge crosses the contour and was not consumed yet,
    // follow the boundary until it returns to the start.
    for cy in gh - 1
    {
        for cx in gw - 1
        {
            let a = at(&grid, gw, cx, cy)
            let b = at(&grid, gw, cx + 1, cy)
            if (a >= thr) == (b >= thr)
            {
                continue
            }

            if visited[cast(u64, cy) * cast(u64, gw) + cast(u64, cx)]
            {
                continue
            }

            // Trace one closed contour starting at this top-edge crossing.
            visited[cast(u64, cy) * cast(u64, gw) + cast(u64, cx)] = true
            var path: *LinePath?

            var x      = cx
            var y      = cy
            var entry  = 0     // 0 top, 1 right, 2 bottom, 3 left: edge we entered through.
            let startX = cx
            let startY = cy
            var guard  = cast(u64, gw) * cast(u64, gh) * 4

            while guard
            {
                guard -= 1

                let c00 = at(&grid, gw, x, y)
                let c10 = at(&grid, gw, x + 1, y)
                let c01 = at(&grid, gw, x, y + 1)
                let c11 = at(&grid, gw, x + 1, y + 1)

                var config = 0
                if c00 >= thr
                {
                    config |= 1
                }

                if c10 >= thr
                {
                    config |= 2
                }

                if c11 >= thr
                {
                    config |= 4
                }

                if c01 >= thr
                {
                    config |= 8
                }

                if config == 0 or config == 15
                {
                    break
                }

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
                    if entry == 0
                    {
                        exitEdge = center >= thr ? 1 : 3
                    }
                    else if entry == 2
                    {
                        exitEdge = center >= thr ? 3 : 1
                    }
                    else if entry == 1
                    {
                        exitEdge = center >= thr ? 0 : 2
                    }
                    else
                    {
                        exitEdge = center >= thr ? 2 : 0
                    }

                case 10:
                    let center = (c00 + c10 + c01 + c11) * 0.25
                    if entry == 0
                    {
                        exitEdge = center >= thr ? 3 : 1
                    }
                    else if entry == 2
                    {
                        exitEdge = center >= thr ? 1 : 3
                    }
                    else if entry == 3
                    {
                        exitEdge = center >= thr ? 0 : 2
                    }
                    else
                    {
                        exitEdge = center >= thr ? 2 : 0
                    }
                }

                if exitEdge < 0
                {
                    break
                }

                // Sub-pixel crossing point on the exit edge. Grid corner (x, y) is
                // source pixel center (x - 1 + 0.5, y - 1 + 0.5).
                func crossing(va, vb: f32, thr: f32)->f32
                {
                    let d = vb - va
                    if Math.abs(d) < 0.0001
                    {
                        return 0.5
                    }

                    return Math.saturate((thr - va) / d)
                }

                // Add the crop origin before computing the fractional crossing, so
                // floating-point rounding is the same as in the full image grid.
                let gridX = x + bounds.left
                let gridY = y + bounds.top
                var px, py: f32
                switch exitEdge
                {
                case 0:
                    px = gridX - 0.5 + crossing(c00, c10, thr)
                    py = gridY - 0.5

                case 1:
                    px = gridX + 0.5
                    py = gridY - 0.5 + crossing(c10, c11, thr)

                case 2:
                    px = gridX - 0.5 + crossing(c01, c11, thr)
                    py = gridY + 0.5

                case 3:
                    px = gridX - 0.5
                    py = gridY - 0.5 + crossing(c00, c01, thr)
                }

                if not path
                {
                    path = result.newPath()
                    path.start(px, py)
                }
                else
                {
                    path.lineTo(px, py)
                }

                // Mark consumed top-edge crossings so no contour is traced twice.
                if exitEdge == 0
                {
                    visited[cast(u64, y) * cast(u64, gw) + cast(u64, x)] = true
                }
                else if exitEdge == 2
                {
                    visited[cast(u64, (y + 1)) * cast(u64, gw) + cast(u64, x)] = true
                }

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

                if x == startX and y == startY and entry == 0
                {
                    break
                }

                // A contour reaching the padded border must not walk off the grid.
                if x < 0 or y < 0 or x >= gw - 1 or y >= gh - 1
                {
                    break
                }
            }

            if path
            {
                let p = path
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
    if tolerance <= 0
    {
        return
    }

    // Collect the raw points.
    var points: Array!{Vector2}
    for elem in path.elements
    {
        points.add(elem.position)
    }

    if points.count < 3
    {
        return
    }

    var keep: Array!{bool}
    keep.resize(points.count)
    keep[0], keep[points.count - 1] = true

    // Iterative stack instead of recursion.
    var stack: Array!{{ first: u64, last: u64 }}
    stack.add({first: 0, last: points.count - 1})

    while stack.count
    {
        let {first, last} = stack.popBack()
        if last <= first + 1
        {
            continue
        }

        let a      = points[first]
        let b      = points[last]
        let ab     = b - a
        let abLen2 = Math.max(ab.dot(ab), 0.000001)

        var far     = first
        var farDist = 0.0_f32
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
            stack.add({first, last: far})
            stack.add({first: far, last})
        }
    }

    // Rebuild the path with the kept points.
    var kept: Array!{Vector2}
    for i in points.count where keep[i]
    {
        kept.add(points[i])
    }

    path.clear()
    path.start(kept[0].x, kept[0].y)
    for var i = 1_u64; i < kept.count; i += 1
    {
        path.lineTo(kept[i].x, kept[i].y)
    }
}
