#global namespace Svg

using Core, Core.Math

private const ScanTileSide    = 1024

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

// A dense solid fill keeps its authored contours and evaluates coverage at the device scale.
struct ScanFill
{
    bounds:          Rectangle
    bands:           Array'ScanBand
    buckets:         Array'ScanBucket
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

        let bounds = transform.transformBounds(.bounds)
        var area   = bounds
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

        // Keep lazy, tile-local preparation when the destination crops away rows.
        if area.height + 1 >= bounds.height do
            .prepareContours(paths, Math.max(transform.m11, 1.0))

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

private struct ScanRows
{
    crossings:    [..] Array'Crossing
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
        for row in firstRow until lastRow
        {
            let {values: coverage, first, end} = scratch.resolveRow(crossings, row, width, evenOdd, not composite)
            let pixels = image.pixels.storage() + cast(u64, bottomRow - row) * image.rowStride + columnOffset
            if composite
            {
                let output = cast([*] u32, pixels)
                for column in first until end
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

private impl ScanFill
{
    mtd prepareContours(paths: *LinePathList, scale: f32)
    {
        const MinContours = 1024
        let count = paths.paths.count
        if count < MinContours or scale <= .preparedScale do
            return
        let workers = Swag.workerCount()
        if workers < 2 do
            return
        let allocator = Swag.getContext().allocator
        let allocatorType: typeinfo = Swag.Allocator
        if not allocator or Swag.kindOf(allocator) != allocatorType do
            return

        // Each job owns its paths. Use the caller's thread-safe allocator for new
        // buffers and leave contours with other allocators to the scan thread.
        let contours = paths.paths.toSlice()
        let batch    = Math.max(256'u64, count / (cast(u64, workers) * 4))
        parallel for |contours, scale, allocator, batch, count| job in (count - 1) / batch + 1
        {
            let first = job * batch
            for index in first until Math.min(first + batch, count)
            {
                let path = contours[index]
                if not path.polygon.points.allocator do
                    path.polygon.points.allocator = allocator
                if path.polygon.points.allocator == allocator do
                    path.flattenPoints(.Normal, scale)
            }
        }

        .preparedScale = scale
    }

    // Fills spans from the winding of all contours. Horizontal coverage is integrated
    // across each pixel and vertical coverage sampled at four evenly spaced positions.
    mtd const writeCoverage(paths: *LinePathList, transform: Transform2, density: f32, tile: Rectangle, color: Color, evenOdd: bool, scratch: *ScanScratch, image: *Image, composite: bool)
    {
        let width     = cast(s32, tile.width)
        let height    = cast(s32, tile.height)
        let crossings = scratch.startRows(height)
        let origin       = Vector2{tile.x, tile.y}
        let scale        = transform.axisScale()
        let flattenScale = Math.max(scale.x, scale.y) * density
        let useBands     = .bands.count and transform.m12 == 0
        let useBuckets   = .buckets.count and transform.m12 == 0
        let bandCount    = useBuckets ? .buckets.count : (useBands ? .bands.count : 1'u64)
        let axisAligned  = transform.m12 == 0 and transform.m21 == 0
        let uniform      = axisAligned and
                           density == 1 and
                           transform.tx == 0 and
                           transform.ty == 0 and
                           transform.m11 == transform.m22
        let useColumns = axisAligned and
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

                path.flattenPoints(.Normal, flattenScale)

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

                addScanContour(crossings, path.polygon.points.toSlice(), &transform, density, origin, uniform, tile.width)
            }
        }

        var state = ScanRows{crossings, image, width,
                             composite ? image.height - 1 - cast(s32, tile.y) : height - 1,
                             composite ? cast(u64, tile.x) * 4 : 0'u64, color, evenOdd, composite}

        // A band owns its crossing lists and the matching destination rows.
        // Join before the next tile or fill can composite over this one.
        const BandRows = 64
        if composite and
           paths.paths.count >= ScanBandSize * 2 and
           height > BandRows and
           cast(u64, width) * cast(u64, height) >= 64 * 1024 and
           Swag.workerCount() > 1
        {
            let count = (height - 1) / BandRows + 1
            parallel for |&state, height| index in cast(u64, count)
            {
                var localScratch: ScanScratch
                let first = cast(s32, index) * BandRows
                state.resolve(&localScratch, first, Math.min(first + BandRows, height))
            }

            return
        }

        state.resolve(scratch, 0, height)
    }
}
