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

private impl ScanBand
{
    mtd const misses(transform: Transform2, density: f32, tile: Rectangle)->bool
    {
        if not .bounded do
            return false

        let scaledMin = .minY * transform.m22
        let scaledMax = .maxY * transform.m22
        let first     = (scaledMin + transform.ty) * density - tile.y
        let last      = (scaledMax + transform.ty) * density - tile.y

        // Include rounding from flattening and transforming the contour.
        let magnitude = Math.max(Math.max(Math.abs(scaledMin), Math.abs(scaledMax)), Math.abs(transform.ty))
        let margin    = 2.0 + magnitude * density * 0.000001
        return Math.isFinite(first) and
               Math.isFinite(last) and
               Math.isFinite(margin) and
               (Math.max(first, last) < -margin or Math.min(first, last) > tile.height + margin)
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
                    .lastImage     = .rasterize(paths, transform, density, tile, color, evenOdd)
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
}

private impl ScanFill
{
    // Fills spans from the winding of all contours. Horizontal coverage is integrated
    // across each pixel and vertical coverage sampled at four evenly spaced positions.
    mtd rasterize(paths: *LinePathList, transform: Transform2, density: f32, tile: Rectangle, color: Color, evenOdd: bool)->Image
    {
        func addEdge(rows: *Array'Array'Crossing, a, b: Vector2)
        {
            if a.y == b.y or not Math.isFinite(a.x) or not Math.isFinite(a.y) or
               not Math.isFinite(b.x) or not Math.isFinite(b.y) do
                return
            let top    = a.y < b.y ? a : b
            let bottom = a.y < b.y ? b : a
            let limit  = cast(f32, rows.count)
            let start  = cast(u64, Math.clamp(Math.ceil(top.y * VerticalSamples - 0.5), 0.0, limit))
            let end    = cast(u64, Math.clamp(Math.ceil(bottom.y * VerticalSamples - 0.5), 0.0, limit))
            let winding = a.y < b.y ? 1 : -1
            for row in start until end
            {
                let y = (cast(f32, row) + 0.5) / VerticalSamples
                let portion = (cast(f64, y) - cast(f64, top.y)) / (cast(f64, bottom.y) - cast(f64, top.y))
                let x       = cast(f32, cast(f64, top.x) + (cast(f64, bottom.x) - cast(f64, top.x)) * portion)
                rows[row].add(Crossing{x, winding})
            }
        }

        let width  = cast(s32, tile.width)
        let height = cast(s32, tile.height)
        var crossings: Array'Array'Crossing
        crossings.resize(cast(u64, height) * VerticalSamples)
        let origin     = Vector2{tile.x, tile.y}
        let scale      = transform.axisScale()
        let useBands   = .bands.count and transform.m12 == 0
        let useBuckets = .buckets.count and transform.m12 == 0
        let bandCount  = useBuckets ? .buckets.count : (useBands ? .bands.count : 1'u64)
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
                let points = path.polygon.points.toSlice()
                if points.count < 2 do
                    continue
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
        var coverage: Array'f32
        coverage.resize(cast(u64, width))
        for row in height
        {
            Memory.clear(coverage.storage(), coverage.count * #sizeof(f32))
            for sample in VerticalSamples
            {
                let line = &crossings[row * VerticalSamples + sample]
                line.sort(func(left, right) => left.x <=> right.x)
                var winding: s32
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

                    winding += crossing.winding
                    previous = x
                }
            }

            let pixels = image.pixels.storage() + cast(u64, height - 1 - row) * image.rowStride
            for column in width
            {
                let pixel = pixels + column * 4
                pixel[0] = color.r
                pixel[1] = color.g
                pixel[2] = color.b
                pixel[3] = cast(u8, Math.round(Math.min(coverage[column] / VerticalSamples, 1) * color.a))
            }
        }

        return image
    }
}
