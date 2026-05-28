using Swag, Core

moduleprivate namespace FreeTypePriv
{
    func renderCurrentOutline(slot: FT_GlyphSlot) throw
    {
        let faceData = getSlotImpl(slot)
        clearBitmap(slot)

        if slot.format != .FT_GLYPH_FORMAT_OUTLINE do
            fail(0x13)

        if slot.outline.n_points <= 0 do
            return

        let bounds = computeOutlineBounds(&slot.outline)
        let left   = Math.floorS32(bounds.minX / 64.0)
        let right  = Math.ceilS32(bounds.maxX / 64.0)
        let bottom = Math.floorS32(bounds.minY / 64.0)
        let top    = Math.ceilS32(bounds.maxY / 64.0)
        let width  = Math.max(0, right - left)
        let rows   = Math.max(0, top - bottom)
        if !width or !rows do
            return

        let edges = buildEdges(&slot.outline)
        if !edges.count do
            return

        faceData.bitmapPixels.resize(cast(u64) width * rows)
        var dst = faceData.bitmapPixels.buffer

        for py in rows
        {
            for px in width
            {
                var hits = 0'u32
                for sy in OVERSAMPLE
                {
                    let sampleY = top - (cast(f64) py + (cast(f64) sy + 0.5) / OVERSAMPLE)
                    for sx in OVERSAMPLE
                    {
                        let sampleX = left + cast(f64) px + (cast(f64) sx + 0.5) / OVERSAMPLE
                        if isInside(edges.toSlice(), sampleX, sampleY) do
                            hits += 1
                    }
                }

                dref dst = cast(u8) ((hits * 255 + (OVERSAMPLE * OVERSAMPLE) / 2) / (OVERSAMPLE * OVERSAMPLE))
                dst += 1
            }
        }

        slot.bitmap.rows         = rows
        slot.bitmap.width        = width
        slot.bitmap.pitch        = cast(s32) width
        slot.bitmap.buffer       = faceData.bitmapPixels.buffer
        slot.bitmap.pixel_mode   = cast(u8) FT_Pixel_Mode.FT_PIXEL_MODE_GRAY
        slot.bitmap.num_grays    = 256
        slot.bitmap_left         = left
        slot.bitmap_top          = top
    }

    func contourSignedArea(points: [..] FT_Vector)->f64
    {
        if @countof(points) < 3 do
            return 0

        var area: f64 = 0.0
        for @countof(points)
        {
            let p0 = points[@index]
            let p1 = points[(@index + 1) % @countof(points)]
            area += cast(f64) p0.x * cast(f64) p1.y - cast(f64) p1.x * cast(f64) p0.y
        }

        return area * 0.5
    }

    func applyEmboldenToContour(points: [..] FT_Vector, strength: f64)
    {
        if @countof(points) < 2 or Math.isZeroEpsilon(cast(f32) strength) do
            return

        var source: Array'FT_Vector
        source.add(points)
        let ccw = contourSignedArea(source.toSlice()) >= 0

        for @countof(points)
        {
            let prev = source[(source.count + @index - 1) % source.count]
            let cur  = source[@index]
            let next = source[(@index + 1) % source.count]

            var e0x = cast(f64) (cur.x - prev.x)
            var e0y = cast(f64) (cur.y - prev.y)
            var e1x = cast(f64) (next.x - cur.x)
            var e1y = cast(f64) (next.y - cur.y)

            let len0 = Math.sqrt(e0x * e0x + e0y * e0y)
            let len1 = Math.sqrt(e1x * e1x + e1y * e1y)
            if Math.isZeroEpsilon(cast(f32) len0)
            {
                e0x = e1x
                e0y = e1y
            }
            if Math.isZeroEpsilon(cast(f32) len1)
            {
                e1x = e0x
                e1y = e0y
            }

            let il0 = Math.isZeroEpsilon(cast(f32) len0) ? 0.0 : 1.0 / Math.max(len0, 0.0001)
            let il1 = Math.isZeroEpsilon(cast(f32) len1) ? 0.0 : 1.0 / Math.max(len1, 0.0001)
            let n0x = ccw ? e0y * il0 : -e0y * il0
            let n0y = ccw ? -e0x * il0 : e0x * il0
            let n1x = ccw ? e1y * il1 : -e1y * il1
            let n1y = ccw ? -e1x * il1 : e1x * il1

            var dirx = n0x + n1x
            var diry = n0y + n1y
            let dirLen = Math.sqrt(dirx * dirx + diry * diry)
            if Math.isZeroEpsilon(cast(f32) dirLen)
            {
                dirx = n1x
                diry = n1y
            }
            else
            {
                dirx /= dirLen
                diry /= dirLen
            }

            let dot    = Math.abs(dirx * n1x + diry * n1y)
            let miter  = dot > 0.25 ? Math.min(4.0, 1.0 / dot) : 1.0
            points[@index].x = cast(s32) Math.round(cur.x + dirx * strength * miter)
            points[@index].y = cast(s32) Math.round(cur.y + diry * strength * miter)
        }
    }


}
