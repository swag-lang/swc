#global namespace Svg

using Core, Core.Math

private const ScanTileSide    = 1024
private const VerticalSamples = 4

private const ScanBandSize    = 64'u64
private const ScanBucketCount = 128'u64

private struct ScanBand
{
    minY, maxY: f32
    bounded:    bool
}

// Include rounding from flattening and transforming the contour.
#[Swag.Inline]
private func scanIntervalMisses(first, last, scale, translation, density, origin, extent: f32)->bool
{
    let scaledFirst = first * scale
    let scaledLast  = last * scale
    let near        = (scaledFirst + translation) * density - origin
    let far         = (scaledLast + translation) * density - origin
    let magnitude   = Math.max(Math.max(Math.abs(scaledFirst), Math.abs(scaledLast)), Math.abs(translation))
    let margin      = 2.0 + magnitude * density * 0.000001
    return Math.isFinite(near) and
           Math.isFinite(far) and
           Math.isFinite(margin) and
           (Math.max(near, far) < -margin or Math.min(near, far) > extent + margin)
}

private impl ScanBand
{
    mtd const misses(transform: Transform2, density: f32, tile: Rectangle)->bool
    {
        return .bounded and scanIntervalMisses(.minY, .maxY, transform.m22, transform.ty, density, tile.y, tile.height)
    }
}

private struct ScanBucket
{
    bounds:  ScanBand
    indices: Array'u32
}

// A crossing of a horizontal sample line and one directed contour edge.
private struct Crossing
{
    x:       f32
    winding: s32
}

struct ScanScratch
{
    rows:     Array'Array'Crossing
    coverage: Array'f32
    sorted:   Array'Crossing
}

// A dense solid fill keeps its authored contours and evaluates coverage at the device scale.
struct ScanFill
{
    bounds:          Rectangle
    bands:           Array'ScanBand
    buckets:         Array'ScanBucket
    measuredBuckets: bool

    lastTile:      Rectangle
    lastTransform: Transform2
    lastDensity:   f32
    lastImage:     Image
}

impl ScanFill
{
    mtd measureGeometry(paths: const *LinePathList)
    {
        let count = paths.paths.count
        if count < ScanBandSize * 8
        {
            .bounds = paths.controlBounds()
            return
        }

        .bands.reserve((count - 1) / ScanBandSize + 1)
        var band = ScanBand{Swag.F32.Max, -Swag.F32.Max, true}
        for path, index in paths.paths
        {
            let bounds = path.controlBounds()
            if not index do
                .bounds = bounds
            else do
                .bounds.expandToInclude(bounds)

            let lastY = bounds.bottom()
            band.bounded = band.bounded and Math.isFinite(bounds.y) and Math.isFinite(lastY)
            band.minY    = Math.min(band.minY, Math.min(bounds.y, lastY))
            band.maxY    = Math.max(band.maxY, Math.max(bounds.y, lastY))
            if (index + 1) % ScanBandSize == 0 or index + 1 == count
            {
                .bands.add(band)
                band = ScanBand{Swag.F32.Max, -Swag.F32.Max, true}
            }
        }

        // Contours scattered through every band still need the original straight pass.
        let extent = cast(f64, .bounds.height)
        var span   = 0.0'f64
        for &current in .bands do
            span += current.bounded ? cast(f64, current.maxY) - current.minY : extent
        if not Math.isFinite(extent) or span >= extent * cast(f64, .bands.count) * 0.25 do
            .bands.free()
    }

    // Wide authored bands offer little culling when contours were emitted out of spatial order.
    // Group the contours by position once a clipped paint needs the index.
    private mtd measureBuckets(paths: const *LinePathList)
    {
        .measuredBuckets = true
        let count  = paths.paths.count
        let extent = cast(f64, .bounds.height)
        if count < ScanBandSize * 8 or
           count > Swag.U32.Max or
           not Math.isFinite(extent) or
           extent <= 0 do
            return

        let origin  = cast(f64, .bounds.y)
        let density = cast(f64, ScanBucketCount) / extent
        var buckets: Array'ScanBucket
        buckets.resize(ScanBucketCount)
        var occupied = 0'u64
        for path, index in paths.paths
        {
            let bounds = path.controlBounds()
            let last   = bounds.bottom()
            if not Math.isFinite(bounds.y) or not Math.isFinite(last) do
                return

            let middle = (cast(f64, bounds.y) + last) * 0.5
            let key    = cast(u64, Math.clamp((middle - origin) * density, 0.0'f64, cast(f64, ScanBucketCount - 1)))
            let bucket = &buckets[key]
            let low    = Math.min(bounds.y, last)
            let high   = Math.max(bounds.y, last)
            if bucket.indices.isEmpty()
            {
                bucket.bounds = ScanBand{low, high, true}
                occupied      += 1
            }
            else
            {
                bucket.bounds.minY = Math.min(bucket.bounds.minY, low)
                bucket.bounds.maxY = Math.max(bucket.bounds.maxY, high)
            }

            bucket.indices.add(cast(u32, index))
        }

        var span = 0.0'f64
        for &bucket in buckets where bucket.indices.count do
            span += cast(f64, bucket.bounds.maxY) - bucket.bounds.minY
        if occupied > 1 and span < extent * cast(f64, occupied) * 0.25 do
            .buckets = #move buckets
    }

    // Records a texture whose pixel grid is aligned with the destination's device pixels.
    mtd paint(painter: *Painter, paths: *LinePathList, color: Color, evenOdd: bool)
    {
        let transform = painter.transform()
        let density   = painter.contentScale()
        let target    = painter.recordingTargetSize()
        let surface   = Rectangle{0, 0, cast(f32, target.width) / density, cast(f32, target.height) / density}
        var area      = transform.transformBounds(.bounds)
        area.intersect(surface)
        if painter.hasClippingRect() do
            area.intersect(painter.clippingRect())
        if area.isEmpty() do
            return

        let left   = Math.floor(area.x * density)
        let top    = Math.floor(area.y * density)
        let right  = Math.ceil(area.right() * density)
        let bottom = Math.ceil(area.bottom() * density)
        if not Math.isFinite(left) or not Math.isFinite(top) or
           not Math.isFinite(right) or not Math.isFinite(bottom) do
            return

        let windowHeight  = bottom - top
        let fitsInOneTile = right - left <= ScanTileSide and windowHeight <= ScanTileSide
        if .bands.isEmpty() and
           not .measuredBuckets and
           transform.m12 == 0 and
           (windowHeight > ScanTileSide or windowHeight * 2 < .bounds.height * Math.abs(transform.m22) * density) do
            .measureBuckets(paths)

        var scratch: ScanScratch
        var y = top
        while y < bottom
        {
            var x = left
            while x < right
            {
                let tile = Rectangle{x, y, Math.min(right - x, ScanTileSide), Math.min(bottom - y, ScanTileSide)}
                let sameTransform = transform.m11 == .lastTransform.m11 and transform.m12 == .lastTransform.m12 and
                                    transform.m21 == .lastTransform.m21 and transform.m22 == .lastTransform.m22 and
                                    transform.tx == .lastTransform.tx and transform.ty == .lastTransform.ty
                if not sameTransform or density != .lastDensity or tile != .lastTile or not .lastImage.isValid()
                {
                    .lastImage = Image.create(cast(s32, tile.width), cast(s32, tile.height), .RGBA8)
                    .writeCoverage(paths, transform, density, tile, color, evenOdd, &scratch, &.lastImage, false)
                    .lastTile      = tile
                    .lastDensity   = density
                    .lastTransform = transform
                }

                let texture = painter.renderer().addImage(.lastImage)
                painter.setTransform(Transform2.Identity)
                painter.drawTexture(Rectangle{tile.x / density, tile.y / density, tile.width / density, tile.height / density}, texture)
                painter.setTransform(transform)
                painter.releaseTexture(texture)
                x += tile.width
            }

            y += Math.min(bottom - y, ScanTileSide)
        }

        if not fitsInOneTile do
            .lastImage = {}
    }

    // Blends one solid fill into a bitmap that contains only ink of this color.
    mtd blend(paths: *LinePathList, transform: Transform2, result: *Image, scratch: *ScanScratch, tileSide: s32, color: Color, evenOdd: bool)
    {
        if not color.a do
            return

        var area = transform.transformBounds(.bounds)
        area.intersect({0, 0, cast(f32, result.width), cast(f32, result.height)})
        if area.isEmpty() do
            return

        let left   = Math.floor(area.x)
        let top    = Math.floor(area.y)
        let right  = Math.ceil(area.right())
        let bottom = Math.ceil(area.bottom())
        if not Math.isFinite(left) or
           not Math.isFinite(top) or
           not Math.isFinite(right) or
           not Math.isFinite(bottom) do
            return

        if .bands.isEmpty() and not .measuredBuckets and bottom - top > tileSide do
            .measureBuckets(paths)

        var y = top
        while y < bottom
        {
            let height = Math.min(bottom - y, cast(f32, tileSide))
            var x      = left
            while x < right
            {
                let width = Math.min(right - x, cast(f32, tileSide))
                .writeCoverage(paths, transform, 1, {x, y, width, height}, color, evenOdd, scratch, result, true)
                x += width
            }

            y += height
        }
    }
}

private impl ScanFill
{
    // Fills spans from the winding of all contours. Horizontal coverage is integrated
    // across each pixel and vertical coverage sampled at four evenly spaced positions.
    mtd writeCoverage(paths: *LinePathList, transform: Transform2, density: f32, tile: Rectangle, color: Color, evenOdd: bool, scratch: *ScanScratch, image: *Image, composite: bool)
    {
        func addEdge(rows: [..] Array'Crossing, a, b: Vector2, width: f32)
        {
            if a.y == b.y or
               not Math.isFinite(a.x) or
               not Math.isFinite(a.y) or
               not Math.isFinite(b.x) or
               not Math.isFinite(b.y) do
                return
            let top     = a.y < b.y ? a : b
            let bottom  = a.y < b.y ? b : a
            let limit   = cast(f32, rows.count)
            let start   = cast(u64, Math.clamp(Math.ceil(top.y * VerticalSamples - 0.5), 0.0, limit))
            let end     = cast(u64, Math.clamp(Math.ceil(bottom.y * VerticalSamples - 0.5), 0.0, limit))
            let winding = a.y < b.y ? 1 : -1
            if top.x == bottom.x
            {
                let crossing = Crossing{Math.clamp(top.x, 0, width), winding}
                for row in start until end do
                    rows[row].add(crossing)
                return
            }

            for row in start until end
            {
                let y       = (cast(f32, row) + 0.5) / VerticalSamples
                let portion = (cast(f64, y) - cast(f64, top.y)) / (cast(f64, bottom.y) - cast(f64, top.y))
                let x       = cast(f32, cast(f64, top.x) + (cast(f64, bottom.x) - cast(f64, top.x)) * portion)

                // Crossings outside the tile can share its boundary: between them
                // there is no span of visible pixels, only a change of winding.
                rows[row].add(Crossing{Math.clamp(x, 0, width), winding})
            }
        }

        func sortLine(line: *Array'Crossing, scratch: *Array'Crossing)
        {
            if line.count <= 8
            {
                let points = line.storage()
                for index in 1 until line.count
                {
                    let crossing = points[index]
                    var target   = index
                    while target and points[target - 1].x > crossing.x
                    {
                        points[target] = points[target - 1]
                        target         -= 1
                    }

                    points[target] = crossing
                }

                return
            }

            if line.count < 128
            {
                line.sort(func(left, right) => left.x <=> right.x)
                return
            }

            // Nonnegative f32 values have the same order as their unsigned bits.
            // Radix sorting long lines avoids repeated comparison calls at each sample.
            scratch.resize(line.count)
            var source = line.storage()
            var target = scratch.storage()
            for digit in 4
            {
                let shift = digit * 8
                var offsets: [256] u64
                for index in line.count
                {
                    let key = cast #bit(u32, source[index].x) & 0x7FFF_FFFF
                    offsets[(key >> shift) & 0xFF] += 1
                }

                var total = 0'u64
                for &offset in offsets
                {
                    let count = offset[]
                    offset[] = total
                    total    += count
                }

                for index in line.count
                {
                    let crossing = source[index]
                    let key      = cast #bit(u32, crossing.x) & 0x7FFF_FFFF
                    let bucket   = (key >> shift) & 0xFF
                    target[offsets[bucket]] = crossing
                    offsets[bucket]         += 1
                }

                swap(&source, &target)
            }
        }

        let width    = cast(s32, tile.width)
        let height   = cast(s32, tile.height)
        let rowCount = cast(u64, height) * VerticalSamples
        if scratch.rows.count < rowCount do
            scratch.rows.resize(rowCount)
        let crossings = scratch.rows.toSlice()[0 until rowCount]
        for &line in crossings do
            line.clear()
        let origin      = Vector2{tile.x, tile.y}
        let scale       = transform.axisScale()
        let useBands    = .bands.count and transform.m12 == 0
        let useBuckets  = .buckets.count and transform.m12 == 0
        let bandCount   = useBuckets ? .buckets.count : (useBands ? .bands.count : 1'u64)
        let axisAligned = transform.m12 == 0 and transform.m21 == 0
        let useColumns  = axisAligned and
                          tile.width < .bounds.width * Math.abs(transform.m11) * density and
                          Math.isFinite((.bounds.y * transform.m22 + transform.ty) * density - tile.y) and
                          Math.isFinite((.bounds.bottom() * transform.m22 + transform.ty) * density - tile.y)
        let useRows = axisAligned and tile.height < .bounds.height * Math.abs(transform.m22) * density
        for band in bandCount
        {
            var first = 0'u64
            var end   = paths.paths.count
            var indices: const [..] u32 = []
            if useBuckets
            {
                let bucket = &.buckets[band]
                if bucket.indices.isEmpty() or bucket.bounds.misses(transform, density, tile) do
                    continue
                indices = bucket.indices.toSlice()
                end     = indices.count
            }
            elif useBands
            {
                if .bands[band].misses(transform, density, tile) do
                    continue
                first = band * ScanBandSize
                end   = first + Math.min(ScanBandSize, end - first)
            }

            for index in first until end
            {
                let path = paths.paths[useBuckets ? cast(u64, indices[index]) : index]

                path.flattenPoints(.Normal, Math.max(scale.x, scale.y) * density)

                // A closed contour outside either tile axis contributes no visible span.
                if (useColumns and scanIntervalMisses(path.minBounds.x, path.maxBounds.x, transform.m11, transform.tx, density, tile.x, tile.width)) or
                   (useRows and scanIntervalMisses(path.minBounds.y, path.maxBounds.y, transform.m22, transform.ty, density, tile.y, tile.height))
                {
                    var finite = true
                    for point in path.polygon.points where not point.isFinite()
                    {
                        finite = false
                        break
                    }

                    if finite do
                        continue
                }

                let points = path.polygon.points.toSlice()
                if points.count < 2 do
                    continue
                var previous = transform.transformPoint(points[points.count - 1]) * density - origin
                for point in points
                {
                    let next = transform.transformPoint(point) * density - origin
                    addEdge(crossings, previous, next, tile.width)
                    previous = next
                }
            }
        }

        if scratch.coverage.count < cast(u64, width) do
            scratch.coverage.resize(cast(u64, width))
        let coverage     = scratch.coverage.storage()
        let ink          = color.argb & 0x00FF_FFFF
        let columnOffset = composite ? cast(u64, tile.x) * 4 : 0'u64
        let bottomRow    = composite ? image.height - 1 - cast(s32, tile.y) : height - 1
        for row in height
        {
            Memory.clear(coverage, cast(u64, width) * #sizeof(f32))
            for sample in VerticalSamples
            {
                let line = &crossings[row * VerticalSamples + sample]
                sortLine(line, &scratch.sorted)
                var winding:  s32
                var previous: f32
                for crossing in line
                {
                    let x = crossing.x
                    if x > previous and (evenOdd ? (winding & 1) != 0 : winding != 0)
                    {
                        let first = cast(u64, Math.floor(previous))
                        let last  = cast(u64, Math.ceil(x)) - 1
                        if first == last
                        {
                            coverage[first] += x - previous
                        }
                        else
                        {
                            coverage[first] += cast(f32, first + 1) - previous
                            for column in first + 1 until last do
                                coverage[column] += 1
                            coverage[last] += x - cast(f32, last)
                        }
                    }

                    winding  += crossing.winding
                    previous = x
                }
            }

            let pixels = image.pixels.storage() + cast(u64, bottomRow - row) * image.rowStride + columnOffset
            if composite
            {
                let output = cast([*] u32, pixels)
                for column in width
                {
                    if coverage[column] <= 0 do
                        continue

                    let alpha = coverage[column] >= VerticalSamples ? cast(u32, color.a) :
                                cast(u32, Math.round(coverage[column] / VerticalSamples * color.a))
                    if alpha == 255
                    {
                        output[column] = ink | 0xFF00_0000
                    }
                    elif alpha
                    {
                        let previous = output[column] >> 24
                        let combined = alpha + (previous * (255 - alpha) + 127) / 255
                        output[column] = ink | (combined << 24)
                    }
                }

                continue
            }

            for column in width
            {
                let pixel = pixels + column * 4
                pixel[0] = color.r
                pixel[1] = color.g
                pixel[2] = color.b
                pixel[3] = cast(u8, Math.round(Math.min(coverage[column] / VerticalSamples, 1) * color.a))
            }
        }
    }
}
