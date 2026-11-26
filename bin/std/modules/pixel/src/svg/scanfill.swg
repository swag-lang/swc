#global namespace Svg

using Core, Core.Math

private const ScanTileSide = 1024

private const ScanBandSize    = 64_u64
private const ScanBucketCount = 128_u64

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
    indices: Array!{u32}
}

// A dense solid fill keeps its authored contours and evaluates coverage at the device scale.
struct ScanFill
{
    bounds:          Rectangle
    bands:           Array!{ScanBand}
    buckets:         Array!{ScanBucket}
    measuredBuckets: bool
    preparedScale:   f32

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
            if not index
            {
                .bounds = bounds
            }
            else
            {
                .bounds.expandToInclude(bounds)
            }

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
        var span   = 0.0_f64
        for &current in .bands
        {
            span += current.bounded ? cast(f64, current.maxY) - current.minY : extent
        }

        if not Math.isFinite(extent) or span >= extent * cast(f64, .bands.count) * 0.25
        {
            .bands.free()
        }
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
           extent <= 0
        {
            return
        }

        let origin  = cast(f64, .bounds.y)
        let density = cast(f64, ScanBucketCount) / extent
        var buckets: Array!{ScanBucket}
        buckets.resize(ScanBucketCount)
        var occupied = 0_u64
        for path, index in paths.paths
        {
            let bounds = path.controlBounds()
            let last   = bounds.bottom()
            if not Math.isFinite(bounds.y) or not Math.isFinite(last)
            {
                return
            }

            let middle = (cast(f64, bounds.y) + last) * 0.5
            let key    = cast(u64, Math.clamp((middle - origin) * density, 0.0_f64, cast(f64, ScanBucketCount - 1)))
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

        var span = 0.0_f64
        for &bucket in buckets where bucket.indices.count
        {
            span += cast(f64, bucket.bounds.maxY) - bucket.bounds.minY
        }

        if occupied > 1 and span < extent * cast(f64, occupied) * 0.25
        {
            .buckets = #move buckets
        }
    }

    // Records a texture whose pixel grid is aligned with the destination's device pixels.
    mtd paint(painter: *Painter, paths: *LinePathList, color: Color, evenOdd: bool)
    {
        if painter.recordScanFill(paths, color, evenOdd ? .EvenOdd : .NonZero)
        {
            return
        }

        let transform = painter.transform()
        let density   = painter.contentScale()
        let target    = painter.recordingTargetSize()
        let surface   = Rectangle{0, 0, cast(f32, target.width) / density, cast(f32, target.height) / density}
        var area      = transform.transformBounds(.bounds)
        area.intersect(surface)
        if painter.hasClippingRect()
        {
            area.intersect(painter.clippingRect())
        }

        if area.isEmpty()
        {
            return
        }

        let left   = Math.floor(area.x * density)
        let top    = Math.floor(area.y * density)
        let right  = Math.ceil(area.right() * density)
        let bottom = Math.ceil(area.bottom() * density)
        if not Math.isFinite(left) or
           not Math.isFinite(top) or
           not Math.isFinite(right) or
           not Math.isFinite(bottom)
        {
            return
        }

        let windowHeight  = bottom - top
        let fitsInOneTile = right - left <= ScanTileSide and windowHeight <= ScanTileSide
        if .bands.isEmpty() and
           not .measuredBuckets and
           transform.m12 == 0 and
           (windowHeight > ScanTileSide or windowHeight * 2 < .bounds.height * Math.abs(transform.m22) * density)
        {
            .measureBuckets(paths)
        }

        var scratch: ScanScratch
        var y = top
        while y < bottom
        {
            var x = left
            while x < right
            {
                let tile = Rectangle{x, y, Math.min(right - x, ScanTileSide), Math.min(bottom - y, ScanTileSide)}
                let sameTransform = transform.m11 == .lastTransform.m11 and
                                    transform.m12 == .lastTransform.m12 and
                                    transform.m21 == .lastTransform.m21 and
                                    transform.m22 == .lastTransform.m22 and
                                    transform.tx == .lastTransform.tx and
                                    transform.ty == .lastTransform.ty
                if not sameTransform or
                   density != .lastDensity or
                   tile != .lastTile or
                   not .lastImage.isValid()
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

        if not fitsInOneTile
        {
            .lastImage = {}
        }
    }

    // Blends one solid fill into a bitmap that contains only ink of this color.
    mtd blend(paths: *LinePathList, transform: Transform2, result: *Image, scratch: *ScanScratch, tileSide: s32, color: Color, evenOdd: bool)
    {
        if not color.a
        {
            return
        }

        let bounds = transform.transformBounds(.bounds)
        var area   = bounds
        area.intersect({0, 0, cast(f32, result.width), cast(f32, result.height)})
        if area.isEmpty()
        {
            return
        }

        let left   = Math.floor(area.x)
        let top    = Math.floor(area.y)
        let right  = Math.ceil(area.right())
        let bottom = Math.ceil(area.bottom())
        if not Math.isFinite(left) or
           not Math.isFinite(top) or
           not Math.isFinite(right) or
           not Math.isFinite(bottom)
        {
            return
        }

        if .bands.isEmpty() and not .measuredBuckets and bottom - top > tileSide
        {
            .measureBuckets(paths)

            // Keep lazy, tile-local preparation when the destination crops away rows.
        }

        let scale = Math.max(transform.m11, 1.0)
        if area.height + 1 >= bounds.height
        {
            .prepareContours(paths, scale)

            // A small remainder tile leaves the main tile's row bands as the better split.
        }

        let parallelTileSpan = cast(f32, tileSide) * 1.5
        if .preparedScale >= scale and
           Swag.workerCount() > 1 and
           (right - left >= parallelTileSpan or bottom - top >= parallelTileSpan) and
           right <= 16_777_216 and
           bottom <= 16_777_216
        {
            let tolerance = LinePath.getFlattenDistance(.Normal) / scale
            var cached    = true
            for path in paths.paths where not path.isPolyOnly
            {
                if path.isDirty or not path.isFlatten or path.flattenTolerance > tolerance
                {
                    cached = false
                    break
                }
            }

            if cached
            {
                let columns = cast(u64, Math.ceil((right - left) / cast(f32, tileSide)))
                let rows    = cast(u64, Math.ceil((bottom - top) / cast(f32, tileSide)))
                let count   = columns * rows
                let jobs    = Math.min(4_u64, cast(u64, Swag.workerCount()), count)
                var state   = {scan: me, paths: paths, transform: transform, result: result,
                               left: left, top: top, right: right, bottom: bottom, tileSide: cast(f32, tileSide),
                               columns: columns, count: count, jobs: jobs, color: color, evenOdd: evenOdd}
                parallel for |&state| job in jobs
                {
                    var local: ScanScratch
                    for var index = job; index < state.count; index += state.jobs
                    {
                        let x    = state.left + cast(f32, index % state.columns) * state.tileSide
                        let y    = state.top + cast(f32, index / state.columns) * state.tileSide
                        let tile = Rectangle{x, y, Math.min(state.right - x, state.tileSide), Math.min(state.bottom - y, state.tileSide)}
                        state.scan.writeCoverage(state.paths, state.transform, 1, tile, state.color, state.evenOdd, &local, state.result, true, true)
                    }
                }

                return
            }
        }

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

    mtd const blendPreparedRows(paths: *LinePathList, transform: Transform2, result: *Image, scratch: *ScanScratch, tile: Rectangle, color: Color, evenOdd: bool, first, end: s32)
    {
        .writeCoverage(paths, transform, 1, tile, color, evenOdd, scratch, result, true, true, first, end)
    }
}

private struct ScanRows
{
    crossings:    [..] ScanSample
    image:        *Image
    width:        s32
    bottomRow:    s32
    columnOffset: u64
    color:        Color
    evenOdd:      bool
    composite:    bool
}

private impl ScanRows
{
    mtd resolve(scratch: *ScanScratch, firstRow, lastRow: s32)
    {
        let crossings    = .crossings
        let image        = .image
        let width        = .width
        let color        = .color
        let ink          = color.argb & 0x00FF_FFFF
        let columnOffset = .columnOffset
        let bottomRow    = .bottomRow
        let evenOdd      = .evenOdd
        let composite    = .composite
        let wideOutput   = image.width > 2048
        for row in firstRow until lastRow
        {
            let {values: coverage, first, end} = scratch.resolveRow(crossings, row, width, evenOdd, not composite)
            let pixels = image.pixels.storage() + cast(u64, bottomRow - row) * image.rowStride + columnOffset
            if composite
            {
                let output = cast([*] u32, pixels)
                let full       = Math.Simd.splat(255'u32)
                let zero       = Math.Simd.splat(0'u32)
                let rgb        = Math.Simd.splat(ink)
                let opacity    = Math.Simd.splat(cast(f32, color.a))
                let samples    = Math.Simd.splat(cast(f32, VerticalSamples))
                var laneStart  = first
                while wideOutput and end - laneStart >= 4
                {
                    let values = Math.Simd.load(coverage + laneStart)
                    let scaled = Math.min(values, samples) / VerticalSamples * opacity
                    let alpha  = roundScanAlpha4(scaled)
                    let target = output + laneStart
                    if Math.Simd.allTrue(alpha == full)
                    {
                        Math.Simd.store(target, rgb | 0xFF00_0000'u32)
                    }
                    elif Math.Simd.anyTrue(alpha != zero)
                    {
                        let previous = Math.Simd.load(target)
                        // Add one to the rounded numerator for exact division by 255.
                        let product  = (previous >> 24) * (full - alpha) + 128'u32
                        let combined = alpha + ((product + (product >> 8)) >> 8)
                        Math.Simd.store(target, Math.Simd.select(alpha != zero, rgb | (combined << 24), previous))
                    }
                    laneStart += 4
                }

                for column in laneStart until end
                {
                    if coverage[column] <= 0
                    {
                        continue
                    }

                    let alpha = coverage[column] >= VerticalSamples ? cast(u32, color.a) :
                                cast(u32, Math.round(coverage[column] / VerticalSamples * color.a))
                    if alpha == 255
                    {
                        output[column] = ink | 0xFF00_0000
                    }
                    else if alpha
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

private impl ScanFill
{
    mtd prepareContours(paths: *LinePathList, scale: f32)
    {
        func addEdge(rows: *Array!{Array!{Crossing}}, a, b: Vector2)
        {
            if a.y == b.y or
               not Math.isFinite(a.x) or
               not Math.isFinite(a.y) or
               not Math.isFinite(b.x) or
               not Math.isFinite(b.y)
            {
                return
            }

            let top     = a.y < b.y ? a : b
            let bottom  = a.y < b.y ? b : a
            let limit   = cast(f32, rows.count)
            let start   = cast(u64, Math.clamp(Math.ceil(top.y * VerticalSamples - 0.5), 0.0, limit))
            let end     = cast(u64, Math.clamp(Math.ceil(bottom.y * VerticalSamples - 0.5), 0.0, limit))
            let winding = a.y < b.y ? 1 : -1
            for row in start until end
            {
                let y       = (cast(f32, row) + 0.5) / VerticalSamples
                let portion = (cast(f64, y) - cast(f64, top.y)) / (cast(f64, bottom.y) - cast(f64, top.y))
                let x       = cast(f32, cast(f64, top.x) + (cast(f64, bottom.x) - cast(f64, top.x)) * portion)
                rows[row].add(Crossing{x, winding})
            }
        }

        let width  = cast(s32, tile.width)
        let height = cast(s32, tile.height)
        var crossings: Array!{Array!{Crossing}}
        crossings.resize(cast(u64, height) * VerticalSamples)
        let origin     = Vector2{tile.x, tile.y}
        let scale      = transform.axisScale()
        let useBands   = .bands.count and transform.m12 == 0
        let useBuckets = .buckets.count and transform.m12 == 0
        let bandCount  = useBuckets ? .buckets.count : (useBands ? .bands.count : 1_u64)
        let useColumns = transform.m12 == 0 and
                         transform.m21 == 0 and
                         tile.width * 2 < .bounds.width * Math.abs(transform.m11) * density and
                         Math.isFinite((.bounds.y * transform.m22 + transform.ty) * density - tile.y) and
                         Math.isFinite((.bounds.bottom() * transform.m22 + transform.ty) * density - tile.y)
        let useRows = axisAligned and tile.height < .bounds.height * Math.abs(transform.m22) * density
        for band in bandCount
        {
            var first = 0_u64
            var end   = paths.paths.count
            var indices: const [..] u32 = []
            if useBuckets
            {
                let bucket = &.buckets[band]
                if bucket.indices.isEmpty() or bucket.bounds.misses(transform, density, tile)
                {
                    continue
                }

                indices = bucket.indices.toSlice()
                end     = indices.count
            }
            else if useBands
            {
                if .bands[band].misses(transform, density, tile)
                {
                    continue
                }

                first = band * ScanBandSize
                end   = first + Math.min(ScanBandSize, end - first)
            }

            for index in first until end
            {
                let path = paths.paths[useBuckets ? cast(u64, indices[index]) : index]

                if not prepared
                {
                    path.flattenPoints(.Normal, flattenScale)

                    // A closed contour outside either tile axis contributes no visible span.
                }

                if (useColumns and scanIntervalMisses(path.minBounds.x, path.maxBounds.x, transform.m11, transform.tx, density, tile.x, tile.width)) or
                   (useRows and scanIntervalMisses(path.minBounds.y, path.maxBounds.y, transform.m22, transform.ty, density, tile.y, tile.height))
                {
                    var finite = true
                    for point in path.polygon.points where not point.isFinite()
                    {
                        finite = false
                        break
                    }

                    if finite
                    {
                        continue
                    }
                }

                path.flattenPoints(.Normal, Math.max(scale.x, scale.y) * density)
                let points = path.polygon.points.toSlice()
                if points.count < 2
                {
                    continue
                }

                var previous = transform.transformPoint(points[points.count - 1]) * density - origin
                for point in points
                {
                    let next = transform.transformPoint(point) * density - origin
                    addEdge(&crossings, previous, next)
                    previous = next
                }
            }
        }

        var image = Image.create(width, height, .RGBA8)
        var coverage: Array!{f32}
        coverage.resize(cast(u64, width))
        for row in height
        {
            let count = (height - 1) / BandRows + 1
            parallel for |&state, height| index in cast(u64, count)
            {
                let line = &crossings[row * VerticalSamples + sample]
                line.sort(func(left, right) => left.x <=> right.x)
                var winding:  s32
                var previous: f32
                for crossing in line
                {
                    let x = Math.clamp(crossing.x, 0, tile.width)
                    if x > previous and (evenOdd ? (winding & 1) != 0 : winding != 0)
                    {
                        let first = cast(u64, Math.floor(previous))
                        let end   = cast(u64, Math.ceil(x))
                        for column in first until end
                        {
                            let edge = cast(f32, column)
                            coverage[column] += Math.min(edge + 1, x) - Math.max(edge, previous)
                        }
                    }

                    winding  += crossing.winding
                    previous = x
                }
            }

            return
        }

        state.resolve(scratch, firstRow, endRow < 0 ? height : endRow)
    }
}
