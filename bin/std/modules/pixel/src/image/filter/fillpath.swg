#global public

using Core, Core.Math

// Decides which points a set of contours encloses.
enum FillRule
{
    NonZero     // Inside where the signed crossing count differs from zero; overlapping contours merge.
    EvenOdd     // Inside where the crossing count is odd; overlapping contours punch holes.
}

// Controls how [[Pixel.Image.fillPath]] resolves coverage.
struct FillPathOptions
{
    rule                 = FillRule.NonZero        // How the contours decide what is inside.
    quality              = PaintQuality.Normal     // Flattening quality applied to curved segments.
    verticalSamples: s32 = 8                       // Scanline samples per pixel row; higher softens near-horizontal edges.
}

// One crossing of a scanline by a contour edge.
private struct Crossing
{
    x:   f32     // Where the edge meets the scanline.
    dir: s32     // '1' when the edge goes down, '-1' when it goes up.
}

public impl Image
{
    // Fills the contours of `paths` with a solid color, in place.
    //
    // This joins [[Pixel.Image.fill]] and [[Pixel.Image.fillGradient2]] in the family that
    // writes an owned pixel buffer immediately, with no renderer and no graphics context, which
    // is what an offline tool needs. [[Pixel.Painter.fillPath]] answers the other layer: it
    // tessellates the same path into geometry for a renderer to draw later, and reaches pixels
    // only through one. Neither replaces the other, and they share no code.
    //
    // Coverage is exact horizontally and sampled `FillPathOptions.verticalSamples` times per row
    // vertically, then composited over the existing pixels in straight alpha. Only 8-bit color
    // formats are filled; anything else is left untouched.
    //
    // ## Example
    //
    // ```swag
    // var path: LinePath
    // path.start(8, 8)
    // path.lineTo(56, 8)
    // path.lineTo(32, 56)
    // path.close()
    //
    // var image = Image.create(64, 64, .RGBA8)
    // image.clear()
    // image.fillPath(path, Color.fromRgb(247, 249, 0))
    // ```
    mtd fillPath(paths: LinePathList, color: Color, options: FillPathOptions = {})
    {
        if .pf.channels() < 3 or .pf.bitDepth() != 8 or !.isValid() do
            return

        var contours: Array'(*Polygon)
        for path in paths.paths
        {
            path.flatten(options.quality)
            let polygon = path.flattenedPolygon()
            if polygon.points.count >= 3 do
                contours.add(polygon)
        }

        .fillContours(contours.toSlice(), color, options)
    }

    // Fills one contour with a solid color.
    mtd fillPath(path: LinePath, color: Color, options: FillPathOptions = {})
    {
        if .pf.channels() < 3 or .pf.bitDepth() != 8 or !.isValid() do
            return

        var copy = path
        copy.flatten(options.quality)
        let polygon = copy.flattenedPolygon()
        if polygon.points.count < 3 do
            return

        var contours: Array'(*Polygon)
        contours.add(polygon)
        .fillContours(contours.toSlice(), color, options)
    }

    // Rasterizes already flattened contours.
    private mtd fillContours(contours: const [..] *Polygon, color: Color, options: FillPathOptions)
    {
        let samples = Math.max(options.verticalSamples, 1)
        let weight  = 1.0 / cast(f32) samples

        var coverage: Array'f32
        coverage.resize(cast(u64) .width)

        var crossings: Array'Crossing

        for [y] in .height
        {
            for &c in coverage do
                c = 0

            for [sub] in samples
            {
                let scanY = cast(f32) y + (cast(f32) sub + 0.5) * weight

                crossings.clear()
                for contour in contours do
                    collectCrossings(&crossings, contour, scanY)
                if crossings.count < 2 do
                    continue

                sortCrossings(crossings.toSlice())

                var winding = 0
                for var i = 0'u64; i + 1 < crossings.count; i += 1
                {
                    winding += crossings[i].dir
                    let inside = options.rule == .NonZero ? winding != 0 : (i & 1) == 0
                    if inside do
                        addSpan(coverage.toSlice(), crossings[i].x, crossings[i + 1].x, weight)
                }
            }

            .blendCoverageRow(y, coverage.toSlice(), color)
        }
    }

    // Composites one row of coverage over the image, in straight alpha.
    private mtd blendCoverageRow(y: s32, coverage: const [..] f32, color: Color)
    {
        // The pixel buffer is stored bottom-up.
        let row      = (notnull .pixels.buffer) + cast(u64) ((.height - 1 - y) * .width8)
        let hasAlpha = .pf.channels() == 4
        let swapped  = .pf == .BGRA8 or .pf == .BGR8

        for [x] in .width
        {
            let srcAlpha = Math.min(coverage[x], 1'f32)
            if srcAlpha <= 0 do
                continue

            let pix      = row + cast(u64) (x * .bpp8)
            let dstAlpha = hasAlpha ? cast(f32) pix[3] / 255.0 : 1.0
            let outAlpha = srcAlpha + dstAlpha * (1 - srcAlpha)
            if outAlpha <= 0 do
                continue

            let first = swapped ? color.b : color.r
            let last  = swapped ? color.r : color.b
            pix[0] = mixChannel(cast(f32) first, srcAlpha, cast(f32) pix[0], dstAlpha, outAlpha)
            pix[1] = mixChannel(cast(f32) color.g, srcAlpha, cast(f32) pix[1], dstAlpha, outAlpha)
            pix[2] = mixChannel(cast(f32) last, srcAlpha, cast(f32) pix[2], dstAlpha, outAlpha)
            if hasAlpha do
                pix[3] = cast(u8) Math.min(outAlpha * 255 + 0.5, 255'f32)
        }
    }
}

// Appends every edge of `contour` that crosses `scanY`.
private func collectCrossings(result: *Array'Crossing, contour: const *Polygon, scanY: f32)
{
    let count = contour.points.count
    for [i] in count
    {
        let p0 = contour.points[i]
        let p1 = contour.points[(i + 1) % count]
        if (p0.y <= scanY) == (p1.y <= scanY) do
            continue

        let t = (scanY - p0.y) / (p1.y - p0.y)
        result.add({p0.x + t * (p1.x - p0.x), p1.y > p0.y ? 1 : -1})
    }
}

// Orders crossings from left to right. A scanline meets few edges, so a straight
// insertion keeps the inner loop free of any call.
private func sortCrossings(crossings: [..] Crossing)
{
    let count = @countof(crossings)
    for var i = 1'u64; i < count; i += 1
    {
        let key = crossings[i]
        var j   = cast(s64) i - 1
        while j >= 0 and crossings[cast(u64) j].x > key.x
        {
            crossings[cast(u64) (j + 1)] = crossings[cast(u64) j]
            j                            -= 1
        }

        crossings[cast(u64) (j + 1)] = key
    }
}

// Accumulates the horizontal overlap of the span into the per-pixel coverage row.
private func addSpan(coverage: [..] f32, x0, x1, weight: f32)
{
    let width = cast(s32) @countof(coverage)
    let left  = Math.max(x0, 0'f32)
    let right = Math.min(x1, cast(f32) width)
    if right <= left do
        return

    var pixel = cast(s32) left
    let last  = Math.min(cast(s32) right, width - 1)
    while pixel <= last
    {
        let pixelLeft = cast(f32) pixel
        let part      = Math.min(right, pixelLeft + 1) - Math.max(left, pixelLeft)
        if part > 0 do
            coverage[pixel] += part * weight
        pixel               += 1
    }
}

#[Swag.Inline]
private func mixChannel(src, srcAlpha, dst, dstAlpha, outAlpha: f32)->u8
{
    let value = (src * srcAlpha + dst * dstAlpha * (1 - srcAlpha)) / outAlpha
    return cast(u8) Math.min(value + 0.5, 255'f32)
}
