using Swag, Core

// How deep a charstring may call subroutines before the font is treated as malformed.
const MaxCharstringDepth = 10_u32

// Largest operand stack a Type 2 charstring may use, as the format defines it.
const MaxCharstringStack = 48_u32

// Accumulates a PostScript outline into the face's reusable point arrays.
//
// Charstring coordinates are design units; the builder scales them to the 26.6 pixels the
// rest of the module works in, so a PostScript glyph reaches the rasterizer in exactly the
// shape a `glyf` glyph does.
struct OutlineBuilder
{
    late face:    *FaceImpl
    scale:        Math.Simd.F64x2
    contourStart: u32
    open:         bool
}

impl OutlineBuilder
{
    func create(face: *FaceImpl, xPpem, yPpem: u32, unitsPerEm: u32)->OutlineBuilder
    {
        var result: #returntype
        result.face = face
        let divisor = cast(f64, Math.max(1_u32, unitsPerEm))
        let xScale  = cast(f64, xPpem) * 64.0 / divisor
        let yScale  = cast(f64, yPpem) * 64.0 / divisor
        result.scale = cast(Math.Simd.F64x2, [xScale, yScale])
        return result
    }

    #[Swag.Inline]
    mtd const scaledPoint(x, y: f64)->Vector
    {
        let rounded = Math.round(cast(Math.Simd.F64x2, [x, y]) * .scale)
        return {x: cast(s32, rounded[0]), y: cast(s32, rounded[1])}
    }

    private mtd addPoint(x, y: f64, tag: u8)
    {
        .face.outlinePoints.add(.scaledPoint(x, y))
        .face.outlineTags.add(tag)
    }

    mtd moveTo(x, y: f64)
    {
        .closeContour()
        .contourStart = cast(u32, .face.outlinePoints.count)
        .addPoint(x, y, CURVE_TAG_ON)
        .open = true
    }

    mtd lineTo(x, y: f64)
    {
        if not .open
        {
            return
        }

        .addPoint(x, y, CURVE_TAG_ON)
    }

    mtd curveTo(c1x, c1y, c2x, c2y, x, y: f64)
    {
        if not .open
        {
            return
        }

        let points = .face.outlinePoints.emplaceAddress(3)
        let tags   = .face.outlineTags.emplaceAddress(3)
        points[0] = .scaledPoint(c1x, c1y)
        points[1] = .scaledPoint(c2x, c2y)
        points[2] = .scaledPoint(x, y)
        tags[0]   = CURVE_TAG_CUBIC
        tags[1]   = CURVE_TAG_CUBIC
        tags[2]   = CURVE_TAG_ON
    }

    // Ends the contour under construction.
    //
    // A PostScript contour is implicitly closed, and its last segment usually lands back on
    // the point it started from. That duplicate is dropped so the decomposer sees the final
    // curve wrap onto the contour start instead of an extra zero-length segment.
    mtd closeContour()
    {
        if not .open
        {
            return
        }

        .open = false

        let points = &.face.outlinePoints
        let tags   = &.face.outlineTags
        var last   = cast(u32, points.count)
        if last > .contourStart + 1
        {
            let tail = last - 1
            let same = points[tail].x == points[.contourStart].x and points[tail].y == points[.contourStart].y
            if same and (tags[tail] & CURVE_TAG_ON) != 0
            {
                points.removeBack()
                tags.removeBack()
                last = tail
            }
        }

        // A contour needs a start and at least one segment; anything shorter is a stray
        // move that would confuse the winding computation.
        if last > .contourStart + 1
        {
            .face.outlineContours.add(cast(s16, (last - 1)))
            return
        }

        points.resize(.contourStart)
        tags.resize(.contourStart)
    }
}

// Everything one run of a Type 2 charstring carries between its operators.
struct Type2State
{
    late font:   *CffFont
    builder:     *OutlineBuilder?
    late subrs:  const *CffIndex
    stack:       [MaxCharstringStack] f64
    transient:   [32] f64
    randomState: u32 = 0x6D2B79F5
    depth:       u32
    x:           f64
    y:           f64
    stems:       u32
    width:       f64
    haveWidth:   bool
    widthOnly:   bool
    finished:    bool

    nominalWidth: f64

    // A composed glyph names its two parts through StandardEncoding and is assembled once
    // the charstring that requested it has ended.
    seacBase:   s32 = -1
    seacAccent: s32 = -1
    seacAdx:    f64
    seacAdy:    f64
}

private impl Type2State
{
    mtd push(value: f64) fail
    {
        if .depth >= MaxCharstringStack
        {
            try fault(0x82)
        }

        .stack[.depth] = value
        .depth         += 1
    }

    // Consumes the optional width that may precede the first stack-clearing operator, and
    // returns the index the operator's own arguments start at.
    mtd takeWidth(expected: u32)->u32
    {
        if .haveWidth
        {
            return 0
        }

        .haveWidth = true
        if .depth <= expected
        {
            return 0
        }

        .width = .nominalWidth + .stack[0]
        return 1
    }

    // Stem operators take pairs, so an odd argument count is what reveals a leading width.
    mtd takeStemWidth()
    {
        if not .haveWidth
        {
            .haveWidth = true
            if (.depth & 1) != 0
            {
                .width = .nominalWidth + .stack[0]
            }
        }

        .stems += .depth / 2
        .depth = 0
    }

    mtd moveTo(x, y: f64)
    {
        .x = x
        .y = y
        .builder?.moveTo(x, y)
    }

    mtd lineTo(x, y: f64)
    {
        .x = x
        .y = y
        .builder?.lineTo(x, y)
    }

    mtd curveTo(c1x, c1y, c2x, c2y, x, y: f64)
    {
        .x = x
        .y = y
        .builder?.curveTo(c1x, c1y, c2x, c2y, x, y)
    }
}

private struct Cff2CharstringState
{
    stack:   [MaxCff2CharstringStack] f64
    vsIndex: u32
    sawIndex, sawBlend: bool

    // Subroutine expansion is bounded independently of nesting depth.
    bytesLeft: u64 = 16 * 1024 * 1024
}

private impl Type2State
{
    mtd const checkPoint(x, y: f64) fail
    {
        if let builder = .builder
        {
            let scaled = Math.round(cast(Math.Simd.F64x2, [x, y]) * builder.scale)
            if not Math.isFinite(scaled[0]) or
               not Math.isFinite(scaled[1]) or
               scaled[0] < Swag.S32.Min or
               scaled[0] > Swag.S32.Max or
               scaled[1] < Swag.S32.Min or
               scaled[1] > Swag.S32.Max
            {
                try fault(0x17)
            }
        }
    }

    #[Swag.Inline]
    mtd(cff2: bool) drawMoveTo(x, y: f64) fail
    {
        #static if cff2
        {
            try .checkPoint(x, y)
        }

        .moveTo(x, y)
    }

    #[Swag.Inline]
    mtd(cff2: bool) drawLineTo(x, y: f64) fail
    {
        #static if cff2
        {
            try .checkPoint(x, y)
        }

        .lineTo(x, y)
    }

    #[Swag.Inline]
    mtd(cff2: bool) drawCurveTo(c1x, c1y, c2x, c2y, x, y: f64) fail
    {
        #static if cff2
        {
            try .checkPoint(c1x, c1y)
            try .checkPoint(c2x, c2y)
            try .checkPoint(x, y)
        }

        .curveTo(c1x, c1y, c2x, c2y, x, y)
    }
}

private func isCff2PathArity(op: u8, count: u32)->bool
{
    switch op
    {
    case 1, 3, 18, 19, 20, 23: return count % 2 == 0
    case 4, 22:                return count == 1
    case 21:                   return count == 2
    case 5:                    return count >= 2 and count % 2 == 0
    case 6, 7:                 return count > 0
    case 8:                    return count >= 6 and count % 6 == 0
    case 24:                   return count >= 8 and (count - 2) % 6 == 0
    case 25:                   return count >= 8 and count % 2 == 0
    case 26, 27, 30, 31:       return count >= 4 and count % 4 <= 1
    default:                   return true
    }
}

#[Swag.Inline]
private func(cff2: bool) pushType2Operand(state: *Type2State, stack: [*] f64, value: f64) fail
{
    #static if cff2
    {
        if state.depth >= MaxCff2CharstringStack
        {
            try fault(0x82)
        }

        stack[state.depth] = value
        state.depth        += 1
    }
    else
    {
        discard stack
        try state.push(value)
    }
}

private func(cff2: bool) execType2(state: *Type2State, code: const [..] u8, depth: u32, variations: *Cff2CharstringState? = null) fail
{
    if depth >= MaxCharstringDepth
    {
        try fault(0x89)
    }

    const StackLimit = cff2 ? MaxCff2CharstringStack : MaxCharstringStack
    let stack = cff2 ? cast([*] f64, &variations!.stack[0]) : cast([*] f64, &state.stack[0])
    #static if cff2
    {
        if code.count > variations!.bytesLeft
        {
            try fault(0x08)
        }

        variations!.bytesLeft -= code.count
    }

    let bytes = code.buffer
    var pos   = 0_u64
    while pos < code.count
    {
        let b0 = bytes[pos]
        pos += 1

        // Most coordinate operands occupy one byte. Keep the stack cursor local
        // until the next operator or multi-byte operand needs the updated depth.
        if b0 >= 32 and b0 <= 246
        {
            var operand = b0
            var count   = state.depth
            for
            {
                if count >= StackLimit
                {
                    state.depth = count
                    try fault(0x82)
                }

                stack[count] = cast(f64, cast(s32, operand) - 139)
                count        += 1
                if pos >= code.count
                {
                    break
                }

                operand = bytes[pos]
                if operand < 32 or operand > 246
                {
                    break
                }

                pos += 1
            }

            state.depth = count
            continue
        }

        if b0 >= 247 or b0 == 28
        {
            #static if cff2
            {
                let operandBytes = b0 == 28 ? 2_u64 : (b0 == 255 ? 4_u64 : 1_u64)
                if code.count - pos < operandBytes
                {
                    try fault(0x08)
                }
            }

            if b0 == 28
            {
                try pushType2Operand!{cff2}(state, stack, cast(f64, peekS16(code, pos)))
                pos += 2
            }
            else if b0 <= 250
            {
                let decodedValue = (cast(s32, b0) - 247) * 256 + cast(s32, peekU8(code, pos)) + 108
                try pushType2Operand!{cff2}(state, stack, cast(f64, decodedValue))
                pos += 1
            }
            else if b0 <= 254
            {
                let decodedValue = -(cast(s32, b0) - 251) * 256 - cast(s32, peekU8(code, pos)) - 108
                try pushType2Operand!{cff2}(state, stack, cast(f64, decodedValue))
                pos += 1
            }
            else
            {
                // A 16.16 fixed-point literal, the only fractional operand the format has.
                try pushType2Operand!{cff2}(state, stack, cast(f64, (try readS32(code, pos))) / 65536.0)
                pos += 4
            }

            continue
        }

        #static if cff2
        {
            if not isCff2PathArity(b0, state.depth)
            {
                try fault(0x08)
            }
        }

        switch b0
        {
        case 1, 3, 18, 23:
            state.takeStemWidth()
            if state.widthOnly
            {
                return
            }

        case 19, 20:
            state.takeStemWidth()
            if state.widthOnly
            {
                return
            }

            let maskBytes = cast(u64, (state.stems + 7)) / 8
            #static if cff2
            {
                if maskBytes > code.count - pos
                {
                    try fault(0x08)
                }
            }

            pos += maskBytes

        case 21:
            let base = state.takeWidth(2)
            if state.widthOnly
            {
                return
            }

            if state.depth >= base + 2
            {
                try state.drawMoveTo!{cff2}(state.x + stack[base], state.y + stack[base + 1])
            }

            state.depth = 0

        case 22:
            let base = state.takeWidth(1)
            if state.widthOnly
            {
                return
            }

            if state.depth >= base + 1
            {
                try state.drawMoveTo!{cff2}(state.x + stack[base], state.y)
            }

            state.depth = 0

        case 4:
            let base = state.takeWidth(1)
            if state.widthOnly
            {
                return
            }

            if state.depth >= base + 1
            {
                try state.drawMoveTo!{cff2}(state.x, state.y + stack[base])
            }

            state.depth = 0

        case 5:
            var i = 0_u32
            while i + 1 < state.depth
            {
                try state.drawLineTo!{cff2}(state.x + stack[i], state.y + stack[i + 1])
                i += 2
            }

            state.depth = 0

        case 6, 7:
            var horizontal = b0 == 6
            for i in state.depth
            {
                if horizontal
                {
                    try state.drawLineTo!{cff2}(state.x + stack[i], state.y)
                }
                else
                {
                    try state.drawLineTo!{cff2}(state.x, state.y + stack[i])
                }

                horizontal = not horizontal
            }

            state.depth = 0

        case 8:
            var i = 0_u32
            while i + 5 < state.depth
            {
                try emitRelativeCurve!{cff2}(state, stack, i)
                i += 6
            }

            state.depth = 0

        case 24:
            var i = 0_u32
            while state.depth >= i + 8
            {
                try emitRelativeCurve!{cff2}(state, stack, i)
                i += 6
            }

            if i + 1 < state.depth
            {
                try state.drawLineTo!{cff2}(state.x + stack[i], state.y + stack[i + 1])
            }

            state.depth = 0

        case 25:
            var i = 0_u32
            while state.depth >= i + 8
            {
                try state.drawLineTo!{cff2}(state.x + stack[i], state.y + stack[i + 1])
                i += 2
            }

            if i + 5 < state.depth
            {
                try emitRelativeCurve!{cff2}(state, stack, i)
            }

            state.depth = 0

        case 26:
            var i     = 0_u32
            var first = 0.0_f64
            if (state.depth & 1) != 0
            {
                first = stack[0]
                i     = 1
            }

            while i + 3 < state.depth
            {
                let c1x = state.x + first
                let c1y = state.y + stack[i]
                let c2x = c1x + stack[i + 1]
                let c2y = c1y + stack[i + 2]
                try state.drawCurveTo!{cff2}(c1x, c1y, c2x, c2y, c2x, c2y + stack[i + 3])
                first = 0
                i     += 4
            }

            state.depth = 0

        case 27:
            var i     = 0_u32
            var first = 0.0_f64
            if (state.depth & 1) != 0
            {
                first = stack[0]
                i     = 1
            }

            while i + 3 < state.depth
            {
                let c1x = state.x + stack[i]
                let c1y = state.y + first
                let c2x = c1x + stack[i + 1]
                let c2y = c1y + stack[i + 2]
                try state.drawCurveTo!{cff2}(c1x, c1y, c2x, c2y, c2x + stack[i + 3], c2y)
                first = 0
                i     += 4
            }

            state.depth = 0

        case 30, 31:
            var horizontal = b0 == 31
            var i = 0_u32
            while i + 3 < state.depth
            {
                // The very last group may carry a fifth argument that moves the axis the
                // alternation would otherwise leave untouched.
                let trailing = state.depth == i + 5 ? stack[i + 4] : 0.0_f64
                if horizontal
                {
                    let c1x = state.x + stack[i]
                    let c1y = state.y
                    let c2x = c1x + stack[i + 1]
                    let c2y = c1y + stack[i + 2]
                    try state.drawCurveTo!{cff2}(c1x, c1y, c2x, c2y, c2x + trailing, c2y + stack[i + 3])
                }
                else
                {
                    let c1x = state.x
                    let c1y = state.y + stack[i]
                    let c2x = c1x + stack[i + 1]
                    let c2y = c1y + stack[i + 2]
                    try state.drawCurveTo!{cff2}(c1x, c1y, c2x, c2y, c2x + stack[i + 3], c2y + trailing)
                }

                horizontal = not horizontal
                i += 4
            }

            state.depth = 0

        case 10, 29:
            if not state.depth
            {
                #static if cff2
                {
                    try fault(0x86)
                }

                break
            }

            state.depth -= 1
            let index = stack[state.depth]
            let table = b0 == 10 ? state.subrs : &state.font.globalSubrs
            var entry: u32
            #static if cff2
            {
                let biased = index + subrBias(table.count())
                if biased < 0 or biased >= table.count() or Math.floor(biased) != biased
                {
                    try fault(0x86)
                }

                entry = cast(u32, biased)
            }
            else
            {
                let biased = cast(s32, index) + subrBias(table.count())
                if biased < 0 or cast(u32, biased) >= table.count()
                {
                    try fault(0x86)
                }

                entry = cast(u32, biased)
            }

            try execType2!{cff2}(state, table.item(entry), depth + 1, variations)

            // The first stack-clearing operator fixes the width even inside a subroutine.
            if state.finished or (state.widthOnly and state.haveWidth)
            {
                return
            }

        case 11:
            #static if cff2
            {
                try fault(0x08)
            }

            return

        case 14:
            #static if cff2
            {
                try fault(0x08)
            }

            if not state.haveWidth
            {
                state.haveWidth = true
                if state.depth == 1 or state.depth == 5
                {
                    state.width = state.nominalWidth + stack[0]
                }
            }

            if state.widthOnly
            {
                state.finished = true
                return
            }

            // Four trailing arguments name an accented glyph built from two others.
            if state.depth >= 4
            {
                let base = state.depth - 4
                state.seacAdx    = stack[base]
                state.seacAdy    = stack[base + 1]
                state.seacBase   = cast(s32, stack[base + 2])
                state.seacAccent = cast(s32, stack[base + 3])
            }

            state.depth    = 0
            state.finished = true
            return

        case 12:
            let b1 = peekU8(code, pos)
            pos += 1
            #static if cff2
            {
                const FlexOperands = [7_u32, 13, 9, 11]
                if b1 < 34 or b1 > 37 or state.depth != FlexOperands[b1 - 34]
                {
                    try fault(0x08)
                }

                for index in state.depth
                {
                    state.stack[index] = stack[index]
                }
            }

            try execType2EscapeImpl!{cff2}(state, b1)

        case 15:
            #static if cff2
            {
                let cursor = unwrap variations
                if state.depth != 1 or cursor.sawIndex or cursor.sawBlend
                {
                    try fault(0x08)
                }

                cursor.vsIndex = try cff2UInt(stack[0])
                if cursor.vsIndex >= state.font.variations.data.count
                {
                    try fault(0x08)
                }

                cursor.sawIndex = true
            }

            state.depth = 0

        case 16:
            #static if cff2
            {
                let cursor = unwrap variations
                let values = Swag.makeSlice(stack, state.depth)
                state.depth     = cast(u32, try blendCff2Operands(&state.font.variations, cursor.vsIndex, values))
                cursor.sawBlend = true
            }
            else
            {
                state.depth = 0
            }

        default:
            #static if cff2
            {
                try fault(0x08)
            }
            else
            {
                state.depth = 0
            }
        }

        #static if cff2
        {
            if let builder = state.builder where builder.face.outlinePoints.count > Swag.S16.Max
            {
                try fault(0x17)
            }
        }
    }
}

// Emits one curve from six consecutive relative arguments.
#[Swag.Inline]
private func(cff2: bool) emitRelativeCurve(state: *Type2State, stack: const [*] f64, i: u32) fail
{
    let c1x = state.x + stack[i]
    let c1y = state.y + stack[i + 1]
    let c2x = c1x + stack[i + 2]
    let c2y = c1y + stack[i + 3]
    try state.drawCurveTo!{cff2}(c1x, c1y, c2x, c2y, c2x + stack[i + 4], c2y + stack[i + 5])
}

// Runs the Type 2 escape operators for curves, arithmetic, logic, stack values, and random values.
func execType2Escape(state: *Type2State, op: u8) fail
{
    try execType2EscapeImpl!{false}(state, op)
}

private func(cff2: bool) execType2EscapeImpl(state: *Type2State, op: u8) fail
{
    switch op
    {
    case 3:
        if state.depth >= 2
        {
            let top = state.depth - 1
            state.stack[top - 1] = (state.stack[top - 1] != 0 and state.stack[top] != 0) ? 1.0 : 0.0
            state.depth -= 1
        }

    case 4:
        if state.depth >= 2
        {
            let top = state.depth - 1
            state.stack[top - 1] = (state.stack[top - 1] != 0 or state.stack[top] != 0) ? 1.0 : 0.0
            state.depth -= 1
        }

    case 5:
        if state.depth
        {
            state.stack[state.depth - 1] = state.stack[state.depth - 1] == 0 ? 1.0 : 0.0
        }

    case 34:
        if state.depth >= 7
        {
            let startY = state.y
            let c1x    = state.x + state.stack[0]
            let c2x    = c1x + state.stack[1]
            let c2y    = startY + state.stack[2]
            let joinX  = c2x + state.stack[3]
            try state.drawCurveTo!{cff2}(c1x, startY, c2x, c2y, joinX, c2y)
            let c3x = joinX + state.stack[4]
            let c4x = c3x + state.stack[5]
            try state.drawCurveTo!{cff2}(c3x, c2y, c4x, startY, c4x + state.stack[6], startY)
        }

        state.depth = 0

    case 35:
        if state.depth >= 13
        {
            try emitRelativeCurve!{cff2}(state, cast(const [*] f64, &state.stack[0]), 0)
            try emitRelativeCurve!{cff2}(state, cast(const [*] f64, &state.stack[0]), 6)
        }

        state.depth = 0

    case 36:
        if state.depth >= 9
        {
            let startY = state.y
            let c1x    = state.x + state.stack[0]
            let c1y    = state.y + state.stack[1]
            let c2x    = c1x + state.stack[2]
            let c2y    = c1y + state.stack[3]
            let joinX  = c2x + state.stack[4]
            try state.drawCurveTo!{cff2}(c1x, c1y, c2x, c2y, joinX, c2y)
            let c3x = joinX + state.stack[5]
            let c4x = c3x + state.stack[6]
            let c4y = c2y + state.stack[7]
            try state.drawCurveTo!{cff2}(c3x, c2y, c4x, c4y, c4x + state.stack[8], startY)
        }

        state.depth = 0

    case 37:
        if state.depth >= 11
        {
            let startX = state.x
            let startY = state.y
            var sumX   = 0.0_f64
            var sumY   = 0.0_f64
            for i in 5_u32
            {
                sumX += state.stack[i * 2]
                sumY += state.stack[i * 2 + 1]
            }

            try emitRelativeCurve!{cff2}(state, cast(const [*] f64, &state.stack[0]), 0)
            let c3x = state.x + state.stack[6]
            let c3y = state.y + state.stack[7]
            let c4x = c3x + state.stack[8]
            let c4y = c3y + state.stack[9]

            // The last argument moves along whichever axis the flex travelled furthest on;
            // the other returns exactly to where the flex began.
            if Math.abs(sumX) > Math.abs(sumY)
            {
                try state.drawCurveTo!{cff2}(c3x, c3y, c4x, c4y, c4x + state.stack[10], startY)
            }
            else
            {
                try state.drawCurveTo!{cff2}(c3x, c3y, c4x, c4y, startX, c4y + state.stack[10])
            }
        }

        state.depth = 0

    case 9:
        if state.depth
        {
            state.stack[state.depth - 1] = Math.abs(state.stack[state.depth - 1])
        }

    case 10:
        if state.depth >= 2
        {
            state.stack[state.depth - 2] += state.stack[state.depth - 1]
            state.depth -= 1
        }

    case 11:
        if state.depth >= 2
        {
            state.stack[state.depth - 2] -= state.stack[state.depth - 1]
            state.depth -= 1
        }

    case 12:
        if state.depth >= 2 and state.stack[state.depth - 1] != 0
        {
            state.stack[state.depth - 2] /= state.stack[state.depth - 1]
            state.depth -= 1
        }

    case 14:
        if state.depth
        {
            state.stack[state.depth - 1] = -state.stack[state.depth - 1]
        }

    case 15:
        if state.depth >= 2
        {
            let top = state.depth - 1
            state.stack[top - 1] = state.stack[top - 1] == state.stack[top] ? 1.0 : 0.0
            state.depth -= 1
        }

    case 18:
        if state.depth
        {
            state.depth -= 1
        }

    case 24:
        if state.depth >= 2
        {
            state.stack[state.depth - 2] *= state.stack[state.depth - 1]
            state.depth -= 1
        }

    case 26:
        if state.depth
        {
            state.stack[state.depth - 1] = Math.sqrt(Math.abs(state.stack[state.depth - 1]))
        }

    case 27:
        if state.depth
        {
            try state.push(state.stack[state.depth - 1])
        }

    case 28:
        if state.depth >= 2
        {
            let top = state.stack[state.depth - 1]
            state.stack[state.depth - 1] = state.stack[state.depth - 2]
            state.stack[state.depth - 2] = top
        }

    case 29:
        if state.depth
        {
            state.depth -= 1
            if state.depth and state.depth < MaxCharstringStack
            {
                let requested = cast(s32, state.stack[state.depth])
                let index     = Math.clamp(requested, 0, cast(s32, state.depth - 1))
                state.stack[state.depth] = state.stack[state.depth - 1 - cast(u32, index)]
                state.depth += 1
            }
        }

    case 30:
        if state.depth >= 2
        {
            let top            = state.depth - 1
            let requestedCount = cast(s32, state.stack[top - 1])
            let rotation       = cast(s32, state.stack[top])
            state.depth -= 2
            if requestedCount > 1 and cast(u32, requestedCount) <= state.depth
            {
                let count = cast(u32, requestedCount)
                let base  = state.depth - count
                var values: [MaxCharstringStack] f64
                for i in count
                {
                    values[i] = state.stack[base + i]
                }

                var shift = rotation % cast(s32, count)
                if shift < 0
                {
                    shift += cast(s32, count)
                }

                for i in count
                {
                    state.stack[base + (i + cast(u32, shift)) % count] = values[i]
                }
            }
        }

    case 20:
        if state.depth >= 2
        {
            let slot = cast(s32, state.stack[state.depth - 1])
            if slot >= 0 and slot < 32
            {
                state.transient[slot] = state.stack[state.depth - 2]
            }

            state.depth -= 2
        }

    case 21:
        if state.depth
        {
            let slot = cast(s32, state.stack[state.depth - 1])
            state.stack[state.depth - 1] = slot >= 0 and slot < 32 ? state.transient[slot] : 0.0
        }

    case 22:
        if state.depth >= 4
        {
            let base        = state.depth - 4
            let whenTrue    = state.stack[base]
            let whenFalse   = state.stack[base + 1]
            let firstValue  = state.stack[base + 2]
            let secondValue = state.stack[base + 3]
            state.stack[base] = firstValue <= secondValue ? whenTrue : whenFalse
            state.depth       = base + 1
        }

    case 23:

        // Repeatable output keeps a glyph stable across renders while satisfying the
        // Type 2 requirement that the generated value lies strictly between zero and one.
        var value = state.randomState
        value ^= value << 13
        value ^= value >> 17
        value ^= value << 5
        state.randomState = value
        try state.push((cast(f64, state.randomState) + 0.5) / 4294967296.0)

    default:
        state.depth = 0
    }
}

private enum Type2WidthResult
{
    Resume
    Default
    Explicit
    Interpret
}

private struct Type2WidthStack
{
    values: [MaxCharstringStack] f64
    count:  u32
}

// Reads the literal operators and subroutine calls that introduce most glyph widths.
// Programs that compute operands use the full interpreter.
private func resolveType2Width(code: const [..] u8, localSubrs, globalSubrs: const *CffIndex, stack: *Type2WidthStack, depth: u32)->Type2WidthResult
{
    if depth >= MaxCharstringDepth
    {
        return .Interpret
    }

    let bytes = code.buffer
    var pos   = 0_u64
    while pos < code.count
    {
        let first = bytes[pos]
        pos += 1
        if first >= 32 or first == 28
        {
            if stack.count >= MaxCharstringStack
            {
                return .Interpret
            }

            var value: f64
            if first >= 32 and first <= 246
            {
                value = cast(f64, (cast(s32, first) - 139))
            }
            else if first >= 247 and first <= 254
            {
                if pos == code.count
                {
                    return .Interpret
                }

                let tail = cast(s32, bytes[pos]) + 108
                value = first <= 250 ? cast(f64, (cast(s32, first) - 247) * 256 + tail) :
                        cast(f64, (251 - cast(s32, first)) * 256 - tail)
                pos += 1
            }
            else
            {
                let length = first == 28 ? 2_u64 : 4_u64
                if length > code.count - pos
                {
                    return .Interpret
                }

                let packed = readPackedOffset(bytes + pos, cast(u8, length))
                value = first == 28 ? cast(f64, cast #bit (s16, cast(u16, packed))) :
                        cast(f64, cast #bit (s32, packed)) / 65536.0
                pos += length
            }

            stack.values[stack.count] = value
            stack.count += 1
            continue
        }

        switch first
        {
        case 1, 3, 18, 19, 20, 23:
            return stack.count & 1 ? .Explicit : .Default

        case 4, 22:
            return stack.count > 1 ? .Explicit : .Default

        case 21:
            return stack.count > 2 ? .Explicit : .Default

        case 14:
            return stack.count == 1 or stack.count == 5 ? .Explicit : .Default

        case 10, 29:
            if not stack.count
            {
                continue
            }

            stack.count -= 1
            let table = first == 10 ? localSubrs : globalSubrs
            let index = cast(s32, stack.values[stack.count]) + subrBias(table.count())
            if index < 0 or cast(u32, index) >= table.count()
            {
                return .Interpret
            }

            let answer = resolveType2Width(table.item(cast(u32, index)), localSubrs, globalSubrs, stack, depth + 1)
            if answer != .Resume
            {
                return answer
            }

        case 11:
            return .Resume

        default:
            return .Interpret
        }
    }

    return .Resume
}

func type2CharstringWidth(font: *CffFont, gid: u32)->f64 fail
{
    if gid >= font.charStrings.count()
    {
        try fault(0x10)
    }

    let privateDict = font.privateFor(gid)
    var stack: Type2WidthStack
    let answer      = resolveType2Width(font.charStrings.item(gid), &privateDict.subrs, &font.globalSubrs, &stack, 0)
    switch #complete answer
    {
    case .Explicit:         return privateDict.nominalWidth + stack.values[0]
    case .Default, .Resume: return privateDict.defaultWidth
    case .Interpret:        return try runType2Charstring(font, gid, null)
    }
}

private func runCff2Charstring(state: *Type2State, code: const [..] u8, vsIndex: u32) fail
{
    var variations: Cff2CharstringState
    variations.vsIndex = vsIndex
    state.haveWidth    = true
    try execType2!{true}(state, code, 0, &variations)
    if state.depth
    {
        try fault(0x08)
    }

    if let builder = state.builder
    {
        builder.closeContour()
        let points = &builder.face.outlinePoints
        if points.count > 1
        {
            // The points can fit individually while the slot's width or height cannot.
            let outline = Outline.borrowed(points.buffer, null, null, cast(s16, points.count), 0)
            let bounds  = computeOutlineBounds(&outline)
            if cast(s64, bounds.maxX) - bounds.minX > Swag.S32.Max or
               cast(s64, bounds.maxY) - bounds.minY > Swag.S32.Max
            {
                try fault(0x17)
            }
        }
    }
}

// Runs one Type 2 charstring and returns the advance width its font declares for the glyph.
//
// Pass a null `builder` to resolve the width alone, which stops at the first stack-clearing
// operator instead of interpreting the whole outline.
func runType2Charstring(font: *CffFont, gid: u32, builder: *OutlineBuilder?)->f64 fail
{
    if gid >= font.charStrings.count()
    {
        try fault(0x10)
    }

    let glyphPrivate = font.privateFor(gid)
    with var state: Type2State
    {
        .font         = font
        .builder      = builder
        .subrs        = &glyphPrivate.subrs
        .nominalWidth = glyphPrivate.nominalWidth
        .width        = glyphPrivate.defaultWidth
        .widthOnly    = builder == null
    }

    let code = font.charStrings.item(gid)
    if font.isCff2
    {
        try runCff2Charstring(&state, code, glyphPrivate.vsIndex)
        return 0.0
    }

    try execType2!{false}(&state, code, 0)
    builder?.closeContour()

    // A composed glyph is drawn as its base plus its accent, placed by the offsets the
    // charstring ended with. Both parts are named through StandardEncoding, never by index.
    if builder and
       state.seacBase >= 0 and
       state.seacBase < 256 and
       state.seacAccent >= 0 and
       state.seacAccent < 256
    {
        let baseGid   = cffGlyphForStandardCode(font, cast(u8, state.seacBase))
        let accentGid = cffGlyphForStandardCode(font, cast(u8, state.seacAccent))
        if baseGid
        {
            discard try runType2Charstring(font, baseGid, builder)
        }

        if accentGid
        {
            try runComposedAccent(font, accentGid, builder, state.seacAdx, state.seacAdy)
        }
    }

    return state.width
}

// Draws an accent displaced by the offsets a composed glyph declared.
private func runComposedAccent(font: *CffFont, gid: u32, builder: *OutlineBuilder, adx, ady: f64) fail
{
    let first = cast(u32, builder.face.outlinePoints.count)
    discard try runType2Charstring(font, gid, builder)

    let delta = builder.scaledPoint(adx, ady)
    for i in first until cast(u32, builder.face.outlinePoints.count)
    {
        builder.face.outlinePoints[i].x += delta.x
        builder.face.outlinePoints[i].y += delta.y
    }
}

// Resolves the glyph a composed character names, which is always a StandardEncoding code.
func cffGlyphForStandardCode(font: *CffFont, code: u8)->u32
{
    let name = standardEncodingName(code)
    return font.glyphNames.glyphIndex(name)
}

// Everything one run of a Type 1 charstring carries between its operators.
struct Type1State
{
    late font: const *Type1Font
    builder:   *OutlineBuilder?
    stack:     [MaxCharstringStack] f64
    depth:     u32

    // Values the interpreter hands back to the charstring through `pop`, which is how the
    // format returns a result from the callable subroutines the language reserves.
    results:     [MaxCharstringStack] f64
    resultDepth: u32

    x:            f64
    y:            f64
    sideBearingX: f64
    width:        f64
    widthOnly:    bool
    finished:     bool

    // A flex is written as seven moves bracketed by two reserved subroutine calls; the
    // moves are collected here instead of being drawn, then replayed as two curves.
    flexing:   bool
    flexCount: u32
    flexX:     [8] f64
    flexY:     [8] f64

    seacBase:   s32 = -1
    seacAccent: s32 = -1
    seacAdx:    f64
    seacAdy:    f64
    seacAsb:    f64
}

private impl Type1State
{
    mtd push(value: f64) fail
    {
        if .depth >= MaxCharstringStack
        {
            try fault(0x82)
        }

        .stack[.depth] = value
        .depth         += 1
    }

    mtd pushResult(value: f64)
    {
        if .resultDepth < MaxCharstringStack
        {
            .results[.resultDepth] = value
            .resultDepth += 1
        }
    }

    mtd moveTo(x, y: f64)
    {
        .x = x
        .y = y

        if .flexing
        {
            if .flexCount < 8
            {
                .flexX[.flexCount] = x
                .flexY[.flexCount] = y
                .flexCount         += 1
            }

            return
        }

        .builder?.moveTo(x, y)
    }

    mtd lineTo(x, y: f64)
    {
        .x = x
        .y = y
        .builder?.lineTo(x, y)
    }

    mtd curveTo(c1x, c1y, c2x, c2y, x, y: f64)
    {
        .x = x
        .y = y
        .builder?.curveTo(c1x, c1y, c2x, c2y, x, y)
    }

    // Replays a collected flex as the two curves it stands for.
    //
    // The first collected move is a reference point the format uses to decide whether the
    // flex is shallow enough to draw as a straight line; the outline itself is the six
    // that follow.
    mtd emitFlex()
    {
        .flexing = false
        if .flexCount < 7 or not .builder
        {
            return
        }

        .builder.curveTo(.flexX[1], .flexY[1], .flexX[2], .flexY[2], .flexX[3], .flexY[3])
        .builder.curveTo(.flexX[4], .flexY[4], .flexX[5], .flexY[5], .flexX[6], .flexY[6])
        .x = .flexX[6]
        .y = .flexY[6]
    }
}

// Type 1 encodes wide operands as integers.
#[Swag.Inline]
private func readType1Number(code: const [..] u8, first: u8, pos: *u64)->s32 fail
{
    if first <= 246
    {
        return cast(s32, first) - 139
    }

    if first <= 254
    {
        let low = cast(s32, peekU8(code, pos[]))
        pos[] += 1
        let high = cast(s32, first)
        return first <= 250 ? (high - 247) * 256 + low + 108 : -(high - 251) * 256 - low - 108
    }

    let value = try readS32(code, pos[])
    pos[] += 4
    return value
}

private func execType1(state: *Type1State, code: const [..] u8, depth: u32) fail
{
    if depth >= MaxCharstringDepth
    {
        try fault(0x89)
    }

    var pos = 0_u64
    while pos < code.count
    {
        let b0 = peekU8(code, pos)
        pos += 1

        if b0 >= 32
        {
            let operand = try readType1Number(code, b0, &pos)
            try state.push(cast(f64, operand))
            continue
        }

        switch b0
        {
        case 13:
            if state.depth >= 2
            {
                state.sideBearingX = state.stack[0]
                state.width        = state.stack[1]
                state.x            = state.stack[0]
                state.y            = 0
            }

            state.depth = 0
            if state.widthOnly
            {
                state.finished = true
                return
            }

        case 9:
            state.builder?.closeContour()
            state.depth = 0

        case 21:
            if state.depth >= 2
            {
                state.moveTo(state.x + state.stack[0], state.y + state.stack[1])
            }

            state.depth = 0

        case 22:
            if state.depth >= 1
            {
                state.moveTo(state.x + state.stack[0], state.y)
            }

            state.depth = 0

        case 4:
            if state.depth >= 1
            {
                state.moveTo(state.x, state.y + state.stack[0])
            }

            state.depth = 0

        case 5:
            if state.depth >= 2
            {
                state.lineTo(state.x + state.stack[0], state.y + state.stack[1])
            }

            state.depth = 0

        case 6:
            if state.depth >= 1
            {
                state.lineTo(state.x + state.stack[0], state.y)
            }

            state.depth = 0

        case 7:
            if state.depth >= 1
            {
                state.lineTo(state.x, state.y + state.stack[0])
            }

            state.depth = 0

        case 8:
            if state.depth >= 6
            {
                let c1x = state.x + state.stack[0]
                let c1y = state.y + state.stack[1]
                let c2x = c1x + state.stack[2]
                let c2y = c1y + state.stack[3]
                state.curveTo(c1x, c1y, c2x, c2y, c2x + state.stack[4], c2y + state.stack[5])
            }

            state.depth = 0

        case 30:
            if state.depth >= 4
            {
                let c1x = state.x
                let c1y = state.y + state.stack[0]
                let c2x = c1x + state.stack[1]
                let c2y = c1y + state.stack[2]
                state.curveTo(c1x, c1y, c2x, c2y, c2x + state.stack[3], c2y)
            }

            state.depth = 0

        case 31:
            if state.depth >= 4
            {
                let c1x = state.x + state.stack[0]
                let c1y = state.y
                let c2x = c1x + state.stack[1]
                let c2y = c1y + state.stack[2]
                state.curveTo(c1x, c1y, c2x, c2y, c2x, c2y + state.stack[3])
            }

            state.depth = 0

        case 10:
            if not state.depth
            {
                break
            }

            state.depth -= 1
            let index = cast(s32, state.stack[state.depth])
            if index < 0 or cast(u64, index) >= state.font.subrs.count
            {
                try fault(0x86)
            }

            try execType1(state, state.font.codeOf(state.font.subrs[index]), depth + 1)
            if state.finished
            {
                return
            }

        case 11:
            return

        case 14:
            state.finished = true
            return

        case 1, 3:
            state.depth = 0

        case 12:
            let b1 = peekU8(code, pos)
            pos += 1
            try execType1Escape(state, b1)
            if state.finished
            {
                return
            }

        default:
            state.depth = 0
        }
    }
}

private func execType1Escape(state: *Type1State, op: u8) fail
{
    switch op
    {
    case 7:
        if state.depth >= 4
        {
            state.sideBearingX = state.stack[0]
            state.width        = state.stack[2]
            state.x            = state.stack[0]
            state.y            = state.stack[1]
        }

        state.depth = 0
        if state.widthOnly
        {
            state.finished = true
        }

    case 6:
        if state.depth >= 5
        {
            state.seacAsb    = state.stack[0]
            state.seacAdx    = state.stack[1]
            state.seacAdy    = state.stack[2]
            state.seacBase   = cast(s32, state.stack[3])
            state.seacAccent = cast(s32, state.stack[4])
        }

        state.depth    = 0
        state.finished = true

    case 12:
        if state.depth >= 2 and state.stack[state.depth - 1] != 0
        {
            state.stack[state.depth - 2] /= state.stack[state.depth - 1]
            state.depth -= 1
        }

    case 16:
        execType1OtherSubr(state)

    case 17:
        if state.resultDepth
        {
            state.resultDepth -= 1
            try state.push(state.results[state.resultDepth])
        }
        else
        {
            try state.push(0)
        }

    case 33:
        if state.depth >= 2
        {
            state.x = state.stack[0]
            state.y = state.stack[1]
        }

        state.depth = 0

    default:
        state.depth = 0
    }
}

// Runs the reserved subroutines the language routes flex and hint replacement through.
private func execType1OtherSubr(state: *Type1State)
{
    if state.depth < 2
    {
        state.depth = 0
        return
    }

    let other = cast(s32, state.stack[state.depth - 1])
    var count = cast(u32, state.stack[state.depth - 2])
    state.depth -= 2
    if count > state.depth
    {
        count = state.depth
    }

    state.resultDepth = 0
    switch other
    {
    case 1:
        state.flexing   = true
        state.flexCount = 0
        state.depth     -= count

    case 2:
        state.depth -= count

    case 0:
        state.emitFlex()
        state.depth -= count

        // The two pops that follow read back the point the flex ended on, in the order
        // `setcurrentpoint` expects to find its arguments.
        state.pushResult(state.y)
        state.pushResult(state.x)

    default:

        // Every other reserved subroutine is an identity: hint replacement passes the
        // number of the subroutine to call straight back through `pop`.
        for i in count
        {
            state.pushResult(state.stack[state.depth - 1 - i])
        }

        state.depth -= count
    }
}

func type1CharstringWidth(font: const *Type1Font, gid: u32)->f64 fail
{
    if gid >= font.charstrings.count
    {
        try fault(0x10)
    }

    let code = font.codeOf(font.charstrings[gid])
    var pos  = 1_u64
    let lsb  = peekU8(code, 0)
    if lsb >= 32
    {
        discard try readType1Number(code, lsb, &pos)
        let encodedWidth = peekU8(code, pos)
        if encodedWidth >= 32
        {
            pos += 1
            let width = try readType1Number(code, encodedWidth, &pos)

            // A leading pair of operands followed by hsbw declares the width.
            if peekU8(code, pos) == 13
            {
                return cast(f64, width)
            }
        }
    }

    return try runType1Charstring(font, gid, null)
}

// Runs one Type 1 charstring and returns the advance width it declares.
//
// Pass a null `builder` to resolve the width alone, which stops at the sidebearing operator
// every charstring opens with.
func runType1Charstring(font: const *Type1Font, gid: u32, builder: *OutlineBuilder?)->f64 fail
{
    if cast(u64, gid) >= font.charstrings.count
    {
        try fault(0x10)
    }

    var state: Type1State
    state.font      = font
    state.builder   = builder
    state.widthOnly = builder == null

    try execType1(&state, font.codeOf(font.charstrings[gid]), 0)
    builder?.closeContour()

    if builder and
       state.seacBase >= 0 and
       state.seacBase < 256 and
       state.seacAccent >= 0 and
       state.seacAccent < 256
    {
        let baseGid   = type1GlyphForStandardCode(font, cast(u8, state.seacBase))
        let accentGid = type1GlyphForStandardCode(font, cast(u8, state.seacAccent))
        if baseGid
        {
            discard try runType1Charstring(font, baseGid, builder)

            // The accent is placed relative to the base glyph's own sidebearing, which is what
            // keeps a composed glyph aligned when the two parts were drawn with different ones.
        }

        if accentGid
        {
            try runType1ComposedAccent(font, accentGid, builder, state.seacAdx - state.seacAsb + state.sideBearingX, state.seacAdy)
        }
    }

    return state.width
}

private func runType1ComposedAccent(font: const *Type1Font, gid: u32, builder: *OutlineBuilder, adx, ady: f64) fail
{
    let first = cast(u32, builder.face.outlinePoints.count)
    discard try runType1Charstring(font, gid, builder)

    let delta = builder.scaledPoint(adx, ady)
    for i in first until cast(u32, builder.face.outlinePoints.count)
    {
        builder.face.outlinePoints[i].x += delta.x
        builder.face.outlinePoints[i].y += delta.y
    }
}

func type1GlyphForStandardCode(font: const *Type1Font, code: u8)->u32
{
    let name = standardEncodingName(code)
    if not name.count
    {
        return 0
    }

    return font.nameToGid.getOrDefault(name, 0)
}
