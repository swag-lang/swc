using Swag, Core

// How deep a charstring may call subroutines before the font is treated as malformed.
const MaxCharstringDepth = 10'u32

// Largest operand stack a Type 2 charstring may use, as the format defines it.
const MaxCharstringStack = 48'u32

// Accumulates a PostScript outline into the face's reusable point arrays.
//
// Charstring coordinates are design units; the builder scales them to the 26.6 pixels the
// rest of the module works in, so a PostScript glyph reaches the rasterizer in exactly the
// shape a `glyf` glyph does.
struct OutlineBuilder
{
    #[Swag.Late]
    face:         *FaceImpl
    scaleX:       f64
    scaleY:       f64
    contourStart: u32
    open:         bool
}

impl OutlineBuilder
{
    func create(face: *FaceImpl, xPpem, yPpem: u32, unitsPerEm: u32)->OutlineBuilder
    {
        var result: retval
        result.face   = face
        result.scaleX = cast(f64) xPpem * 64.0 / cast(f64) Math.max(1'u32, unitsPerEm)
        result.scaleY = cast(f64) yPpem * 64.0 / cast(f64) Math.max(1'u32, unitsPerEm)
        return result
    }

    private mtd addPoint(x, y: f64, tag: u8)
    {
        .face.outlinePoints.add(Vector{x: cast(s32) Math.round(x * .scaleX), y: cast(s32) Math.round(y * .scaleY)})
        .face.outlineTags.add(tag)
    }

    mtd moveTo(x, y: f64)
    {
        .closeContour()
        .contourStart = cast(u32) .face.outlinePoints.count
        .addPoint(x, y, CURVE_TAG_ON)
        .open = true
    }

    mtd lineTo(x, y: f64)
    {
        if !.open do
            return
        .addPoint(x, y, CURVE_TAG_ON)
    }

    mtd curveTo(c1x, c1y, c2x, c2y, x, y: f64)
    {
        if !.open do
            return
        .addPoint(c1x, c1y, CURVE_TAG_CUBIC)
        .addPoint(c2x, c2y, CURVE_TAG_CUBIC)
        .addPoint(x, y, CURVE_TAG_ON)
    }

    // Ends the contour under construction.
    //
    // A PostScript contour is implicitly closed, and its last segment usually lands back on
    // the point it started from. That duplicate is dropped so the decomposer sees the final
    // curve wrap onto the contour start instead of an extra zero-length segment.
    mtd closeContour()
    {
        if !.open do
            return
        .open = false

        let points = &.face.outlinePoints
        let tags   = &.face.outlineTags
        var last   = cast(u32) points.count
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
            .face.outlineContours.add(cast(s16) (last - 1))
            return
        }

        points.resize(.contourStart)
        tags.resize(.contourStart)
    }
}

// Everything one run of a Type 2 charstring carries between its operators.
struct Type2State
{
    #[Swag.Late]
    font:    *CffFont
    builder: #null *OutlineBuilder
    #[Swag.Late]
    subrs:     const *CffIndex
    stack:     [MaxCharstringStack] f64
    transient: [32] f64
    depth:     u32
    x:         f64
    y:         f64
    stems:     u32
    width:     f64
    haveWidth: bool
    widthOnly: bool
    finished:  bool

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
    mtd push(value: f64)
    {
        if .depth < MaxCharstringStack
        {
            .stack[.depth] = value
            .depth         += 1
        }
    }

    // Consumes the optional width that may precede the first stack-clearing operator, and
    // returns the index the operator's own arguments start at.
    mtd takeWidth(expected: u32)->u32
    {
        if .haveWidth do
            return 0
        .haveWidth = true
        if .depth <= expected do
            return 0
        .width = .nominalWidth + .stack[0]
        return 1
    }

    // Stem operators take pairs, so an odd argument count is what reveals a leading width.
    mtd takeStemWidth()
    {
        if !.haveWidth
        {
            .haveWidth = true
            if (.depth & 1) != 0 do
                .width = .nominalWidth + .stack[0]
        }

        .stems += .depth / 2
        .depth = 0
    }

    mtd moveTo(x, y: f64)
    {
        .x = x
        .y = y
        if .builder do
            .builder!.moveTo(x, y)
    }

    mtd lineTo(x, y: f64)
    {
        .x = x
        .y = y
        if .builder do
            .builder!.lineTo(x, y)
    }

    mtd curveTo(c1x, c1y, c2x, c2y, x, y: f64)
    {
        .x = x
        .y = y
        if .builder do
            .builder!.curveTo(c1x, c1y, c2x, c2y, x, y)
    }
}

private func execType2(state: *Type2State, code: #null const [..] u8, depth: u32) fail
{
    if depth >= MaxCharstringDepth do
        fault(0x89)

    var pos = 0'u64
    while pos < code.count
    {
        let b0 = readU8(code, pos)
        pos += 1

        if b0 >= 32 or b0 == 28
        {
            if b0 == 28
            {
                state.push(cast(f64) readS16(code, pos))
                pos += 2
            }
            elif b0 <= 246
            {
                state.push(cast(f64) (cast(s32) b0 - 139))
            }
            elif b0 <= 250
            {
                state.push(cast(f64) ((cast(s32) b0 - 247) * 256 + cast(s32) readU8(code, pos) + 108))
                pos += 1
            }
            elif b0 <= 254
            {
                state.push(cast(f64) (-(cast(s32) b0 - 251) * 256 - cast(s32) readU8(code, pos) - 108))
                pos += 1
            }
            else
            {
                // A 16.16 fixed-point literal, the only fractional operand the format has.
                state.push(cast(f64) readS32(code!, pos) / 65536.0)
                pos += 4
            }

            continue
        }

        switch b0
        {
        case 1, 3, 18, 23:
            state.takeStemWidth()
            if state.widthOnly do
                return

        case 19, 20:
            state.takeStemWidth()
            if state.widthOnly do
                return
            pos += cast(u64) (state.stems + 7) / 8

        case 21:
            let base = state.takeWidth(2)
            if state.widthOnly do
                return
            if state.depth >= base + 2 do
                state.moveTo(state.x + state.stack[base], state.y + state.stack[base + 1])
            state.depth = 0

        case 22:
            let base = state.takeWidth(1)
            if state.widthOnly do
                return
            if state.depth >= base + 1 do
                state.moveTo(state.x + state.stack[base], state.y)
            state.depth = 0

        case 4:
            let base = state.takeWidth(1)
            if state.widthOnly do
                return
            if state.depth >= base + 1 do
                state.moveTo(state.x, state.y + state.stack[base])
            state.depth = 0

        case 5:
            var i = 0'u32
            while i + 1 < state.depth
            {
                state.lineTo(state.x + state.stack[i], state.y + state.stack[i + 1])
                i += 2
            }

            state.depth = 0

        case 6, 7:
            var horizontal = b0 == 6
            for i in state.depth
            {
                if horizontal do
                    state.lineTo(state.x + state.stack[i], state.y)
                else do
                    state.lineTo(state.x, state.y + state.stack[i])
                horizontal = !horizontal
            }

            state.depth = 0

        case 8:
            var i = 0'u32
            while i + 5 < state.depth
            {
                emitRelativeCurve(state, i)
                i += 6
            }

            state.depth = 0

        case 24:
            var i = 0'u32
            while state.depth >= i + 8
            {
                emitRelativeCurve(state, i)
                i += 6
            }

            if i + 1 < state.depth do
                state.lineTo(state.x + state.stack[i], state.y + state.stack[i + 1])
            state.depth = 0

        case 25:
            var i = 0'u32
            while state.depth >= i + 8
            {
                state.lineTo(state.x + state.stack[i], state.y + state.stack[i + 1])
                i += 2
            }

            if i + 5 < state.depth do
                emitRelativeCurve(state, i)
            state.depth = 0

        case 26:
            var i     = 0'u32
            var first = 0.0'f64
            if (state.depth & 1) != 0
            {
                first = state.stack[0]
                i     = 1
            }

            while i + 3 < state.depth
            {
                let c1x = state.x + first
                let c1y = state.y + state.stack[i]
                let c2x = c1x + state.stack[i + 1]
                let c2y = c1y + state.stack[i + 2]
                state.curveTo(c1x, c1y, c2x, c2y, c2x, c2y + state.stack[i + 3])
                first = 0
                i     += 4
            }

            state.depth = 0

        case 27:
            var i     = 0'u32
            var first = 0.0'f64
            if (state.depth & 1) != 0
            {
                first = state.stack[0]
                i     = 1
            }

            while i + 3 < state.depth
            {
                let c1x = state.x + state.stack[i]
                let c1y = state.y + first
                let c2x = c1x + state.stack[i + 1]
                let c2y = c1y + state.stack[i + 2]
                state.curveTo(c1x, c1y, c2x, c2y, c2x + state.stack[i + 3], c2y)
                first = 0
                i     += 4
            }

            state.depth = 0

        case 30, 31:
            var horizontal = b0 == 31
            var i          = 0'u32
            while i + 3 < state.depth
            {
                // The very last group may carry a fifth argument that moves the axis the
                // alternation would otherwise leave untouched.
                let trailing = state.depth == i + 5 ? state.stack[i + 4] : 0.0'f64
                if horizontal
                {
                    let c1x = state.x + state.stack[i]
                    let c1y = state.y
                    let c2x = c1x + state.stack[i + 1]
                    let c2y = c1y + state.stack[i + 2]
                    state.curveTo(c1x, c1y, c2x, c2y, c2x + trailing, c2y + state.stack[i + 3])
                }
                else
                {
                    let c1x = state.x
                    let c1y = state.y + state.stack[i]
                    let c2x = c1x + state.stack[i + 1]
                    let c2y = c1y + state.stack[i + 2]
                    state.curveTo(c1x, c1y, c2x, c2y, c2x + state.stack[i + 3], c2y + trailing)
                }

                horizontal = !horizontal
                i          += 4
            }

            state.depth = 0

        case 10, 29:
            if !state.depth do
                break
            state.depth -= 1
            let index = state.stack[state.depth]
            let table = b0 == 10 ? state.subrs : &state.font.globalSubrs
            let entry = cast(s32) index + subrBias(table.count())
            if entry < 0 or cast(u32) entry >= table.count() do
                fault(0x86)
            execType2(state, table.item(state.font.block, cast(u32) entry), depth + 1)
            if state.finished do
                return

        case 11:
            return

        case 14:
            if !state.haveWidth
            {
                state.haveWidth = true
                if state.depth == 1 or state.depth == 5 do
                    state.width = state.nominalWidth + state.stack[0]
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
                state.seacAdx    = state.stack[base]
                state.seacAdy    = state.stack[base + 1]
                state.seacBase   = cast(s32) state.stack[base + 2]
                state.seacAccent = cast(s32) state.stack[base + 3]
            }

            state.depth    = 0
            state.finished = true
            return

        case 12:
            let b1 = readU8(code, pos)
            pos += 1
            execType2Escape(state, b1)

        default:
            state.depth = 0
        }
    }
}

// Emits one curve from six consecutive relative arguments.
private func emitRelativeCurve(state: *Type2State, i: u32)
{
    let c1x = state.x + state.stack[i]
    let c1y = state.y + state.stack[i + 1]
    let c2x = c1x + state.stack[i + 2]
    let c2y = c1y + state.stack[i + 3]
    state.curveTo(c1x, c1y, c2x, c2y, c2x + state.stack[i + 4], c2y + state.stack[i + 5])
}

// Runs the two-byte operators: the four flex forms and the arithmetic set.
private func execType2Escape(state: *Type2State, op: u8)
{
    switch op
    {
    case 34:
        if state.depth >= 7
        {
            let startY = state.y
            let c1x    = state.x + state.stack[0]
            let c2x    = c1x + state.stack[1]
            let c2y    = startY + state.stack[2]
            let joinX  = c2x + state.stack[3]
            state.curveTo(c1x, startY, c2x, c2y, joinX, c2y)
            let c3x = joinX + state.stack[4]
            let c4x = c3x + state.stack[5]
            state.curveTo(c3x, c2y, c4x, startY, c4x + state.stack[6], startY)
        }

        state.depth = 0

    case 35:
        if state.depth >= 13
        {
            emitRelativeCurve(state, 0)
            emitRelativeCurve(state, 6)
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
            state.curveTo(c1x, c1y, c2x, c2y, joinX, c2y)
            let c3x = joinX + state.stack[5]
            let c4x = c3x + state.stack[6]
            let c4y = c2y + state.stack[7]
            state.curveTo(c3x, c2y, c4x, c4y, c4x + state.stack[8], startY)
        }

        state.depth = 0

    case 37:
        if state.depth >= 11
        {
            let startX = state.x
            let startY = state.y
            var sumX   = 0.0'f64
            var sumY   = 0.0'f64
            for i in 5'u32
            {
                sumX += state.stack[i * 2]
                sumY += state.stack[i * 2 + 1]
            }

            emitRelativeCurve(state, 0)
            let c3x = state.x + state.stack[6]
            let c3y = state.y + state.stack[7]
            let c4x = c3x + state.stack[8]
            let c4y = c3y + state.stack[9]

            // The last argument moves along whichever axis the flex travelled furthest on;
            // the other returns exactly to where the flex began.
            if Math.abs(sumX) > Math.abs(sumY) do
                state.curveTo(c3x, c3y, c4x, c4y, c4x + state.stack[10], startY)
            else do
                state.curveTo(c3x, c3y, c4x, c4y, startX, c4y + state.stack[10])
        }

        state.depth = 0

    case 9:
        if state.depth do
            state.stack[state.depth - 1] = Math.abs(state.stack[state.depth - 1])

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
        if state.depth do
            state.stack[state.depth - 1] = -state.stack[state.depth - 1]

    case 18:
        if state.depth do
            state.depth -= 1

    case 24:
        if state.depth >= 2
        {
            state.stack[state.depth - 2] *= state.stack[state.depth - 1]
            state.depth -= 1
        }

    case 26:
        if state.depth do
            state.stack[state.depth - 1] = Math.sqrt(Math.abs(state.stack[state.depth - 1]))

    case 27:
        if state.depth and state.depth < MaxCharstringStack
        {
            state.stack[state.depth] = state.stack[state.depth - 1]
            state.depth              += 1
        }

    case 28:
        if state.depth >= 2
        {
            let top = state.stack[state.depth - 1]
            state.stack[state.depth - 1] = state.stack[state.depth - 2]
            state.stack[state.depth - 2] = top
        }

    case 20:
        if state.depth >= 2
        {
            let slot = cast(s32) state.stack[state.depth - 1]
            if slot >= 0 and slot < 32 do
                state.transient[slot] = state.stack[state.depth - 2]
            state.depth -= 2
        }

    case 21:
        if state.depth
        {
            let slot = cast(s32) state.stack[state.depth - 1]
            state.stack[state.depth - 1] = slot >= 0 and slot < 32 ? state.transient[slot] : 0.0
        }

    default:
        state.depth = 0
    }
}

// Runs one Type 2 charstring and returns the advance width its font declares for the glyph.
//
// Pass a null `builder` to resolve the width alone, which stops at the first stack-clearing
// operator instead of interpreting the whole outline.
func runType2Charstring(font: *CffFont, gid: u32, builder: #null *OutlineBuilder)->f64 fail
{
    if gid >= font.charStrings.count() do
        fault(0x10)

    let glyphPrivate = font.privateFor(gid)
    var state: Type2State
    state.font         = font
    state.builder      = builder
    state.subrs        = glyphPrivate.subrs
    state.nominalWidth = glyphPrivate.nominalWidth
    state.width        = glyphPrivate.defaultWidth
    state.widthOnly    = builder == null

    execType2(&state, font.charStrings.item(font.block, gid), 0)
    if builder do
        builder!.closeContour()

    // A composed glyph is drawn as its base plus its accent, placed by the offsets the
    // charstring ended with. Both parts are named through StandardEncoding, never by index.
    if builder and state.seacBase >= 0 and state.seacBase < 256 and state.seacAccent >= 0 and state.seacAccent < 256
    {
        let baseGid   = cffGlyphForStandardCode(font, cast(u8) state.seacBase)
        let accentGid = cffGlyphForStandardCode(font, cast(u8) state.seacAccent)
        if baseGid do
            discard runType2Charstring(font, baseGid, builder)
        if accentGid do
            runComposedAccent(font, accentGid, builder!, state.seacAdx, state.seacAdy)
    }

    return state.width
}

// Draws an accent displaced by the offsets a composed glyph declared.
private func runComposedAccent(font: *CffFont, gid: u32, builder: *OutlineBuilder, adx, ady: f64) fail
{
    let first = cast(u32) builder.face.outlinePoints.count
    discard runType2Charstring(font, gid, builder)

    let dx = cast(s32) Math.round(adx * builder.scaleX)
    let dy = cast(s32) Math.round(ady * builder.scaleY)
    for i in first until cast(u32) builder.face.outlinePoints.count
    {
        builder.face.outlinePoints[i].x += dx
        builder.face.outlinePoints[i].y += dy
    }
}

// Resolves the glyph a composed character names, which is always a StandardEncoding code.
func cffGlyphForStandardCode(font: *CffFont, code: u8)->u32
{
    let name = standardEncodingName(code)
    if !name.count do
        return 0
    return font.nameToGid.getOrDefault(String.from(name), 0)
}

// Everything one run of a Type 1 charstring carries between its operators.
struct Type1State
{
    #[Swag.Late]
    font:    *Type1Font
    builder: #null *OutlineBuilder
    stack:   [MaxCharstringStack] f64
    depth:   u32

    // Values the interpreter hands back to the charstring through `pop`, which is how the
    // format returns a result from the callable subroutines the language reserves.
    results:     [32] f64
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
    mtd push(value: f64)
    {
        if .depth < MaxCharstringStack
        {
            .stack[.depth] = value
            .depth         += 1
        }
    }

    mtd pushResult(value: f64)
    {
        if .resultDepth < 32
        {
            .results[.resultDepth] = value
            .resultDepth           += 1
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

        if .builder do
            .builder!.moveTo(x, y)
    }

    mtd lineTo(x, y: f64)
    {
        .x = x
        .y = y
        if .builder do
            .builder!.lineTo(x, y)
    }

    mtd curveTo(c1x, c1y, c2x, c2y, x, y: f64)
    {
        .x = x
        .y = y
        if .builder do
            .builder!.curveTo(c1x, c1y, c2x, c2y, x, y)
    }

    // Replays a collected flex as the two curves it stands for.
    //
    // The first collected move is a reference point the format uses to decide whether the
    // flex is shallow enough to draw as a straight line; the outline itself is the six
    // that follow.
    mtd emitFlex()
    {
        .flexing = false
        if .flexCount < 7 or !.builder do
            return
        .builder!.curveTo(.flexX[1], .flexY[1], .flexX[2], .flexY[2], .flexX[3], .flexY[3])
        .builder!.curveTo(.flexX[4], .flexY[4], .flexX[5], .flexY[5], .flexX[6], .flexY[6])
        .x = .flexX[6]
        .y = .flexY[6]
    }
}

private func execType1(state: *Type1State, code: #null const [..] u8, depth: u32) fail
{
    if depth >= MaxCharstringDepth do
        fault(0x89)

    var pos = 0'u64
    while pos < code.count
    {
        let b0 = readU8(code, pos)
        pos += 1

        if b0 >= 32
        {
            if b0 <= 246
            {
                state.push(cast(f64) (cast(s32) b0 - 139))
            }
            elif b0 <= 250
            {
                state.push(cast(f64) ((cast(s32) b0 - 247) * 256 + cast(s32) readU8(code, pos) + 108))
                pos += 1
            }
            elif b0 <= 254
            {
                state.push(cast(f64) (-(cast(s32) b0 - 251) * 256 - cast(s32) readU8(code, pos) - 108))
                pos += 1
            }
            else
            {
                // Type 1 spells its wide literals as plain 32-bit integers, not as the
                // fixed-point form Type 2 introduced for the same encoding byte.
                state.push(cast(f64) readS32(code!, pos))
                pos += 4
            }

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
            if state.builder do
                state.builder!.closeContour()
            state.depth = 0

        case 21:
            if state.depth >= 2 do
                state.moveTo(state.x + state.stack[0], state.y + state.stack[1])
            state.depth = 0

        case 22:
            if state.depth >= 1 do
                state.moveTo(state.x + state.stack[0], state.y)
            state.depth = 0

        case 4:
            if state.depth >= 1 do
                state.moveTo(state.x, state.y + state.stack[0])
            state.depth = 0

        case 5:
            if state.depth >= 2 do
                state.lineTo(state.x + state.stack[0], state.y + state.stack[1])
            state.depth = 0

        case 6:
            if state.depth >= 1 do
                state.lineTo(state.x + state.stack[0], state.y)
            state.depth = 0

        case 7:
            if state.depth >= 1 do
                state.lineTo(state.x, state.y + state.stack[0])
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
            if !state.depth do
                break
            state.depth -= 1
            let index = cast(s32) state.stack[state.depth]
            if index < 0 or cast(u64) index >= state.font.subrs.count do
                fault(0x86)
            execType1(state, state.font.subrs[index].toSlice(), depth + 1)
            if state.finished do
                return

        case 11:
            return

        case 14:
            state.finished = true
            return

        case 1, 3:
            state.depth = 0

        case 12:
            let b1 = readU8(code, pos)
            pos += 1
            execType1Escape(state, b1)
            if state.finished do
                return

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
        if state.widthOnly do
            state.finished = true

    case 6:
        if state.depth >= 5
        {
            state.seacAsb    = state.stack[0]
            state.seacAdx    = state.stack[1]
            state.seacAdy    = state.stack[2]
            state.seacBase   = cast(s32) state.stack[3]
            state.seacAccent = cast(s32) state.stack[4]
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
            state.push(state.results[state.resultDepth])
        }
        else
        {
            state.push(0)
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

    let other = cast(s32) state.stack[state.depth - 1]
    var count = cast(u32) state.stack[state.depth - 2]
    state.depth -= 2
    if count > state.depth do
        count = state.depth

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
        for i in count do
            state.pushResult(state.stack[state.depth - 1 - i])
        state.depth -= count
    }
}

// Runs one Type 1 charstring and returns the advance width it declares.
//
// Pass a null `builder` to resolve the width alone, which stops at the sidebearing operator
// every charstring opens with.
func runType1Charstring(font: *Type1Font, gid: u32, builder: #null *OutlineBuilder)->f64 fail
{
    if cast(u64) gid >= font.charstrings.count do
        fault(0x10)

    var state: Type1State
    state.font      = font
    state.builder   = builder
    state.widthOnly = builder == null

    execType1(&state, font.charstrings[gid].toSlice(), 0)
    if builder do
        builder!.closeContour()

    if builder and state.seacBase >= 0 and state.seacBase < 256 and state.seacAccent >= 0 and state.seacAccent < 256
    {
        let baseGid   = type1GlyphForStandardCode(font, cast(u8) state.seacBase)
        let accentGid = type1GlyphForStandardCode(font, cast(u8) state.seacAccent)
        if baseGid do
            discard runType1Charstring(font, baseGid, builder)

        // The accent is placed relative to the base glyph's own sidebearing, which is what
        // keeps a composed glyph aligned when the two parts were drawn with different ones.
        if accentGid do
            runType1ComposedAccent(font, accentGid, builder!, state.seacAdx - state.seacAsb + state.sideBearingX, state.seacAdy)
    }

    return state.width
}

private func runType1ComposedAccent(font: *Type1Font, gid: u32, builder: *OutlineBuilder, adx, ady: f64) fail
{
    let first = cast(u32) builder.face.outlinePoints.count
    discard runType1Charstring(font, gid, builder)

    let dx = cast(s32) Math.round(adx * builder.scaleX)
    let dy = cast(s32) Math.round(ady * builder.scaleY)
    for i in first until cast(u32) builder.face.outlinePoints.count
    {
        builder.face.outlinePoints[i].x += dx
        builder.face.outlinePoints[i].y += dy
    }
}

func type1GlyphForStandardCode(font: *Type1Font, code: u8)->u32
{
    let name = standardEncodingName(code)
    if !name.count do
        return 0
    return font.nameToGid.getOrDefault(String.from(name), 0)
}
