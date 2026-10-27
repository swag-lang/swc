// @LICENCE: LGPL-2.1-or-later
// @ORIGIN: FFmpeg n7.1, libavcodec/rv34.c and rv40.c
// @MODIFIED: 2026-10-27, Swag decoder with bounded packets and owned reference pictures.
// @NOTICE: THIRDPARTY.md#ffmpeg-realvideo-decoder
#global namespace RealVideo
#global internal

using Core, Core.Errors

const Intra4        = 0's32
const Intra16       = 1's32
const Pred16        = 2's32
const Pred8         = 3's32
const Forward       = 4's32
const Backward      = 5's32
const Skip          = 6's32
const Direct        = 7's32
const Pred16x8      = 8's32
const Pred8x16      = 9's32
const Bidirectional = 10's32
const Mixed16       = 11's32

#[Swag.NoCopy]
struct Decoder
{
    width:       s32
    height:      s32
    current:     Frame
    past:        Frame
    future:      Frame
    bits:        Bits
    header:      SliceHeader
    modes:       Array's32
    modeStride:  s32
    blockAt:     s32
    skipRun:     s32
    available:   [12] bool
    table:       s32
    interTable:  bool
    pictureKind: s32
}

impl Decoder
{
    mtd configure(width, height: s32) fail
    {
        if width <= 0 or height <= 0 or width > 8192 or height > 8192 do
            fail InvalidFormatError{"RealVideo picture dimensions exceed the supported range"}
        .width  = width
        .height = height
        .reset()
    }

    mtd reset()
    {
        .past.valid   = false
        .future.valid = false
    }

    mtd chooseTable(inter: bool)
    {
        var quant = .header.quant
        if .header.set == 2 and quant < 19 do
            quant += 10
        elif .header.set != 0 and quant < 26 do
            quant += 5
        .interTable = inter
        .table      = QuantSet[(inter ? 32 : 0) + quant]
    }

    mtd coefficient(value, escape, quant: s32)->s32
    {
        var result = value
        if not result do
            return 0
        if result == escape
        {
            result = .bits.code(.interTable ? InterCoeff[.table] : IntraCoeff[.table])
            if result > 23
            {
                let width = cast(u32, (result - 23))
                result = 22 + (1 << width) + cast(s32, .bits.read(width))
            }

            result += escape
        }

        if .bits.read(1) do
            result = -result
        let scaled = (result * quant + 8) >> 4
        if scaled < -32768 or scaled > 32767
        {
            .bits.broken = true
            return 0
        }

        return scaled
    }

    mtd subblock(block: *[16] s32, offset, code: s32, transpose: bool, dc, ac1, ac2: s32)
    {
        block[][offset]                       = .coefficient(code / 27, 3, dc)
        block[][offset + (transpose ? 4 : 1)] = .coefficient(code / 9 % 3, 2, ac1)
        block[][offset + (transpose ? 1 : 4)] = .coefficient(code / 3 % 3, 2, ac1)
        block[][offset + 5]                   = .coefficient(code % 3, 2, ac2)
    }

    mtd coefficients(first, second, dc, ac1, ac2: s32)->[16] s32
    {
        var result: #returntype
        let root    = .interTable ? InterFirst[.table * 2 + first] : IntraFirst[.table * 4 + first]
        let code    = .bits.code(root)
        let pattern = code & 7
        .subblock(&result, 0, code >> 3, false, dc, ac1, ac2)
        if (pattern & 4) != 0 do
            .subblock(&result, 2, .bits.code(.interTable ? InterSecond[.table * 2 + second] : IntraSecond[.table * 2 + second]), false, ac2, ac2, ac2)
        if (pattern & 2) != 0 do
            .subblock(&result, 8, .bits.code(.interTable ? InterSecond[.table * 2 + second] : IntraSecond[.table * 2 + second]), true, ac2, ac2, ac2)
        if (pattern & 1) != 0 do
            .subblock(&result, 10, .bits.code(.interTable ? InterThird[.table * 2 + second] : IntraThird[.table * 2 + second]), false, ac2, ac2, ac2)
        return result
    }

    mtd codedPattern(is16: bool)->u32
    {
        let selector = cast(s32, is16)
        var code     = .bits.code(.interTable ? InterCbpPattern[.table] : IntraCbpPattern[.table * 2 + selector])
        let pattern  = code & 15
        code >>= 4
        const Ones = [0, 0, 0, 1, 0, 1, 1, 2, 0, 1, 1, 2, 1, 2, 2, 3]
        const Shifts: [4] u32 = [0, 2, 8, 10]
        let count  = Ones[pattern]
        var result = 0'u32
        for i in 4'u32
        {
            if (pattern & (8 >> i)) != 0
            {
                let root = .interTable ? InterCbp[.table * 4 + count] : IntraCbp[.table * 8 + count * 2 + selector]
                result |= cast(u32, .bits.code(root)) << Shifts[i]
            }
        }

        const Divisors = [27, 9, 3, 1]
        for i in 4'u32
        {
            let part = code / Divisors[i] % 3
            if part == 1 do
                result |= (.bits.read(1) != 0 ? 0x010000'u32 : 0x100000'u32) << i
            elif part == 2 do
                result |= 0x110000'u32 << i
        }

        return result
    }

    mtd modeAt()->s32 => (.blockAt / .current.columns * 4 + 1) * .modeStride + (.blockAt % .current.columns) * 4 + 1

    mtd readModes()
    {
        let base = .modeAt()
        for row in 4's32
        {
            let start = base + row * .modeStride
            if row == 0 and .blockAt - .header.start < .current.columns
            {
                let pattern = .bits.code(AicTop[0])
                for x in 4's32 do
                    .modes[start + x] = ((pattern >> cast(u32, (3 - x))) & 1) * 2
                continue
            }

            var x = 0's32
            while x < 4
            {
                let pos     = start + x
                let a       = .modes[pos - .modeStride + 1]
                let b       = .modes[pos - .modeStride]
                let c       = .modes[pos - 1]
                let pattern = a + b * 16 + c * 256
                var pair    = -1's32
                for i in 20's32 where AicPatterns[i] == pattern do
                    pair = i
                if x < 3 and pair >= 0
                {
                    let code = .bits.code(AicTwo[pair])
                    .modes[pos]     = code >> 4
                    .modes[pos + 1] = code & 15
                    x += 2
                    continue
                }

                var value: s32
                if b >= 0 and c >= 0 do
                    value = .bits.code(AicOne[b + c * 10])
                elif c == -1 and b < 2 do
                    value = cast(s32, .bits.read(1)) ^ 1
                elif c == 0 or c == 2 do
                    value = (cast(s32, .bits.read(1)) ^ 1) * 2
                .modes[pos] = value
                x += 1
            }
        }
    }

    mtd availability()
    {
        for i in 12 do
            .available[i] = false
        .available[6]  = true
        .available[7]  = true
        .available[10] = true
        .available[11] = true
        let x    = .blockAt % .current.columns
        let dist = .blockAt - .header.start
        .available[5] = x > 0 and dist > 0
        .available[9] = .available[5]
        .available[2] = dist >= .current.columns
        .available[3] = .available[2]
        .available[4] = x + 1 < .current.columns and dist >= .current.columns - 1
        .available[1] = x > 0 and dist > .current.columns
    }

    mtd blockKind()->s32
    {
        if not .skipRun do
            .skipRun = .bits.unsignedCode() + 1
        if .skipRun > .current.columns * .current.rows + 1
        {
            .bits.broken = true
            return Intra4
        }

        .skipRun -= 1
        if .skipRun > 0 do
            return Skip
        var predicted: s32
        if .available[2]
        {
            var counts: [12] s32
            if .available[5] do
                counts[.current.blocks[.blockAt - 1].kind] += 1
            counts[.current.blocks[.blockAt - .current.columns].kind] += 1
            if .available[4] do
                counts[.current.blocks[.blockAt - .current.columns + 1].kind] += 1
            if .available[1] do
                counts[.current.blocks[.blockAt - .current.columns - 1].kind] += 1
            var maximum: s32
            for i in 12's32 where counts[i] > maximum
            {
                maximum   = counts[i]
                predicted = i
                if maximum > 1 do
                    break
            }
        }
        elif .available[5]
        {
            predicted = .current.blocks[.blockAt - 1].kind
        }

        let root = .pictureKind == 2 ? PType[PTypeMap[predicted]] : BType[BTypeMap[predicted]]
        let kind = .bits.code(root)
        if kind >= 12 do
            .bits.broken = true
        return kind < 12 ? kind : 0
    }

    mtd const motionAt(x, y, direction: s32)->Motion
    {
        if x < 0 or y < 0 or x >= .current.columns * 2 or y >= .current.rows * 2 do
            return {}
        return .current.blocks[(y / 2) * .current.columns + x / 2].motion[direction][(y & 1) * 2 + (x & 1)]
    }

    mtd predictedMotion(kind, part: s32, delta: Motion)
    {
        const Widths  = [2, 2, 2, 1, 2, 2, 2, 2, 2, 1, 2, 2]
        const Heights = [2, 2, 2, 1, 2, 2, 2, 2, 1, 2, 2, 2]
        const Slots   = [6, 7, 10, 11]
        let x     = (.blockAt % .current.columns) * 2 + (part & 1)
        let y     = (.blockAt / .current.columns) * 2 + (part >> 1)
        let slot  = Slots[part]
        let right = part == 3 ? -1 : Widths[kind]
        var a: Motion
        if .available[slot - 1] do
            a = .motionAt(x - 1, y, 0)
        let b = .available[slot - 4] ? .motionAt(x, y - 1, 0) : a
        var c = a
        if .available[slot + right - 4] do
            c = .motionAt(x + right, y - 1, 0)
        elif .available[slot - 4] and .available[slot - 1] do
            c = .motionAt(x - 1, y - 1, 0)
        let mv = Motion{median(a.x, b.x, c.x) + delta.x, median(a.y, b.y, c.y) + delta.y}
        for row in Heights[kind]
        {
            for column in Widths[kind] do
                .current.blocks[.blockAt].motion[0][part + row * 2 + column] = mv
        }
    }

    mtd predictedB(direction: s32, delta: Motion)
    {
        var vectors: [3] Motion
        var count:   s32
        let columns = .current.columns
        let x       = .blockAt % columns * 2
        let y       = .blockAt / columns * 2
        if .available[5] and hasDirection(.current.blocks[.blockAt - 1].kind, direction)
        {
            vectors[count] = .motionAt(x - 1, y, direction)
            count += 1
        }

        if .available[2] and hasDirection(.current.blocks[.blockAt - columns].kind, direction)
        {
            vectors[count] = .motionAt(x, y - 1, direction)
            count += 1
        }

        if .available[2] and
           .available[4] and
           hasDirection(.current.blocks[.blockAt - columns + 1].kind, direction)
        {
            vectors[count] = .motionAt(x + 2, y - 1, direction)
            count += 1
        }
        elif .blockAt % columns == columns - 1 and
             .available[1] and
             hasDirection(.current.blocks[.blockAt - columns - 1].kind, direction)
        {
            vectors[count] = .motionAt(x - 1, y - 1, direction)
            count += 1
        }

        var mv: Motion
        if count == 3
        {
            mv = {median(vectors[0].x, vectors[1].x, vectors[2].x), median(vectors[0].y, vectors[1].y, vectors[2].y)}
        }
        else
        {
            for i in count
            {
                mv.x += vectors[i].x
                mv.y += vectors[i].y
            }

            if count == 2
            {
                mv.x /= 2
                mv.y /= 2
            }
        }

        mv.x += delta.x
        mv.y += delta.y
        for part in 4 do
            .current.blocks[.blockAt].motion[direction][part] = mv
    }

    mtd motion(kind: s32) fail
    {
        const Counts = [0, 0, 1, 4, 1, 1, 0, 0, 2, 2, 2, 1]
        var deltas: [4] Motion
        for i in Counts[kind] do
            deltas[i] = {.bits.signedCode(), .bits.signedCode()}
        for delta in deltas where Math.abs(delta.x) > 32767 or Math.abs(delta.y) > 32767 do
            fail InvalidFormatError{"RealVideo motion difference exceeds its signed 16-bit range"}
        if kind <= Intra16 do
            return
        let direct = kind == Direct or (kind == Skip and .pictureKind == 3)
        if .pictureKind == 2 and not .future.valid do
            fail InvalidFormatError{"RealVideo predicted picture has no reference picture"}
        if .pictureKind == 3 and (not .past.valid or not .future.valid) do
            fail InvalidFormatError{"RealVideo bidirectional picture has no reference pictures"}
        if kind == Pred16 or kind == Mixed16
        {
            .predictedMotion(kind, 0, deltas[0])
        }
        elif kind == Pred8
        {
            for i in 4's32 do
                .predictedMotion(kind, i, deltas[i])
        }
        elif kind == Pred16x8 or kind == Pred8x16
        {
            .predictedMotion(kind, 0, deltas[0])
            .predictedMotion(kind, kind == Pred16x8 ? 2 : 1, deltas[1])
        }
        elif kind == Forward or kind == Backward
        {
            .predictedB(kind == Backward ? 1 : 0, deltas[0])
        }
        elif kind == Bidirectional
        {
            .predictedB(0, deltas[0])
            .predictedB(1, deltas[1])
        }

        let distance = (.future.timestamp - .past.timestamp + 8192) & 8191
        let ahead    = (.header.timestamp - .past.timestamp + 8192) & 8191
        let behind   = (.future.timestamp - .header.timestamp + 8192) & 8191
        let w1       = distance != 0 ? (ahead << 14) / distance : 8192
        let w2       = distance != 0 ? (behind << 14) / distance : 8192
        if .pictureKind == 3 and distance != 0 and (ahead > distance or behind > distance) do
            fail InvalidFormatError{"RealVideo bidirectional timestamp lies outside its reference interval"}
        if direct
        {
            for i in 4's32
            {
                let anchor = .future.blocks[.blockAt].motion[0][i]
                .current.blocks[.blockAt].motion[0][i] = {(anchor.x * w1 + 8192) >> 14, (anchor.y * w1 + 8192) >> 14}
                .current.blocks[.blockAt].motion[1][i] = {(-anchor.x * w2 + 8192) >> 14, (-anchor.y * w2 + 8192) >> 14}
            }
        }

        let two = direct or kind == Bidirectional
        for direction in 2
        {
            for vector in .current.blocks[.blockAt].motion[direction] where
                vector.x < -32768 or vector.x > 32767 or vector.y < -32768 or vector.y > 32767 do
                fail InvalidFormatError{"RealVideo motion vector exceeds its signed 16-bit range"}
        }

        for channel in 3's32
        {
            let size  = channel == 0 ? 16 : 8
            let baseX = .blockAt % .current.columns * size
            let baseY = .blockAt / .current.columns * size
            let dst   = .current.planes[channel].at(baseX, baseY)
            for y in size
            {
                for x in size
                {
                    let part      = (y / (size / 2)) * 2 + x / (size / 2)
                    let forward   = .current.blocks[.blockAt].motion[0][part]
                    let backward  = .current.blocks[.blockAt].motion[1][part]
                    let reference = .pictureKind == 2 ? &.future.planes[channel] : &.past.planes[channel]
                    var value: s32
                    if kind != Backward do
                        value = motionPixel(reference, baseX + cast(s32, x), baseY + cast(s32, y), forward, channel != 0)
                    if two or kind == Backward
                    {
                        let next = motionPixel(&.future.planes[channel], baseX + cast(s32, x), baseY + cast(s32, y), backward, channel != 0)
                        if kind == Backward do
                            value = next
                        elif kind == Bidirectional or w1 == 8192 do
                            value = (value + next + 1) >> 1
                        else do
                            value = (((w2 * value) >> 9) + ((w1 * next) >> 9) + 16) >> 5
                    }

                    dst[y * .current.planes[channel].stride + x] = clipped(value)
                }
            }
        }

        if direct
        {
            for i in 4 do
                .current.blocks[.blockAt].motion[0][i] = {}
        }
    }

    mtd macroblock() fail
    {
        .availability()
        let modeBase = .modeAt()
        var kind: s32
        if .pictureKind == 0 do
            kind = .bits.read(1) != 0 ? Intra16 : Intra4
        else do
            kind = .blockKind()
        .current.blocks[.blockAt].kind  = kind == Skip ? (.pictureKind == 2 ? Pred16 : Direct) : kind
        .current.blocks[.blockAt].quant = .header.quant
        if .pictureKind != 0 do
            try .motion(kind)
        let intra = kind == Intra4 or kind == Intra16
        let is16  = kind == Intra16 or kind == Mixed16
        if kind == Intra4
        {
            if .pictureKind == 0 and not .bits.read(1)
            {
                if .bits.broken do
                    fail InvalidFormatError{"RealVideo intra macroblock header is truncated"}
                fail UnsupportedFormatError{"RealVideo intra macroblock requests a quantizer change"}
            }

            .readModes()
        }
        else
        {
            let mode = kind == Intra16 ? cast(s32, .bits.read(2)) : 0
            for y in 4's32
            {
                for x in 4's32 do
                    .modes[modeBase + y * .modeStride + x] = mode
            }
        }

        .chooseTable(not intra and kind != Mixed16)
        let pattern = kind == Skip ? 0'u32 : .codedPattern(is16)
        .current.blocks[.blockAt].cbp     = pattern
        .current.blocks[.blockAt].deblock = intra ? 65535 : ((pattern & 65535) | .motionEdges())
        let luma = kind == Intra4 ? 1 : (is16 ? 2 : 0)
        var dcBlock: [16] s32
        if is16
        {
            let dc = Quant[LumaDcQuant[(kind == Mixed16 ? 32 : 0) + .header.quant]]
            dcBlock = .coefficients(3, 0, dc, dc, Quant[.header.quant])
            inverseTransform(&dcBlock, true)
        }

        for channel in 3's32
        {
            if channel == 1 and kind == Mixed16 do
                .chooseTable(true)
            let size   = channel == 0 ? 16 : 8
            let blocks = size / 4
            let baseX  = .blockAt % .current.columns * size
            let baseY  = .blockAt / .current.columns * size
            let plane  = &.current.planes[channel]
            let quant  = channel == 0 ? Quant[.header.quant] : Quant[ChromaQuant[.header.quant]]
            let dc     = channel == 0 ? quant : Quant[ChromaQuant[32 + .header.quant]]
            if kind == Intra16 do
                predictLarge(plane.at(baseX, baseY), plane.stride, size, .modes[modeBase], .available[2], .available[5])
            var available: [48] bool
            available[0]  = .available[1]
            available[1]  = .available[2]
            available[2]  = .available[2]
            available[3]  = .available[3]
            available[4]  = .available[3]
            available[5]  = .available[4]
            available[8]  = .available[5]
            available[16] = .available[5]
            available[24] = .available[9]
            available[32] = .available[9]
            for y in blocks
            {
                for x in blocks
                {
                    let dst = plane.at(baseX + cast(s32, x) * 4, baseY + cast(s32, y) * 4)
                    let pos = 9 + y * 8 + x
                    if kind == Intra4
                    {
                        if channel == 0
                        {
                            predictSmall(dst, plane.stride, .modes[modeBase + y * .modeStride + x], available[pos - 8], available[pos - 1], available[pos + 7], available[pos - 7])
                        }
                        else
                        {
                            let top   = y > 0 or .available[2]
                            let left  = x > 0 or .available[5]
                            let right = y == 0 ? (x == 0 ? .available[3] : .available[4]) : x == 0
                            predictSmall(dst, plane.stride, .modes[modeBase + y * 2 * .modeStride + x * 2], top, left, x == 0 and y == 0, right)
                        }

                        available[pos] = true
                    }

                    let shift = channel == 0 ? y * 4 + x : 16 + (channel - 1) * 4 + y * 2 + x
                    var coeff: [16] s32
                    if (pattern & (1'u32 << cast(u32, shift))) != 0 do
                        coeff = .coefficients(channel == 0 ? luma : (intra ? 0 : 1), channel == 0 ? 0 : 1, dc, quant, quant)
                    if channel == 0 and is16 do
                        coeff[0] = dcBlock[y * 4 + x]
                    addResidual(dst, plane.stride, &coeff)
                }
            }
        }

        if .bits.broken do
            fail InvalidFormatError{"RealVideo macroblock exceeds its slice or contains an invalid code"}
    }

    mtd motionEdges()->u32
    {
        var horizontalMask = 0'u32
        var verticalMask   = 0'u32
        let x              = .blockAt % .current.columns * 2
        let y              = .blockAt / .current.columns * 2
        for row in 2's32
        {
            for column in 2's32
            {
                let current = .motionAt(x + column, y + row, 0)
                let left    = .motionAt(x + column - 1, y + row, 0)
                let top     = .motionAt(x + column, y + row - 1, 0)
                if Math.abs(current.x - left.x) > 3 or Math.abs(current.y - left.y) > 3 do
                    verticalMask |= 0x11'u32 << cast(u32, (row * 8 + column * 2))
                if (row > 0 or y > 0) and (Math.abs(current.x - top.x) > 3 or Math.abs(current.y - top.y) > 3) do
                    horizontalMask |= 3'u32 << cast(u32, (row * 8 + column * 2))
            }
        }

        if .blockAt - .header.start < .current.columns do
            horizontalMask &= ~15'u32
        if not x do
            verticalMask &= ~0x1111'u32
        return horizontalMask | verticalMask
    }

    mtd decode(payload: const [..] u8, target: *PlanarFrame) fail
    {
        defer #fail .reset()
        let packet = try Packet.open(payload)
        .bits = Bits.open(packet.slice(0))
        let first = try SliceHeader.read(&.bits, .width, .height)
        if first.start != 0 do
            fail InvalidFormatError{"RealVideo picture does not start with its first macroblock"}
        if first.kind != 0 and .future.valid and (first.width != .width or first.height != .height) do
            fail InvalidFormatError{"RealVideo predicted picture changes the reference dimensions"}
        .width       = first.width
        .height      = first.height
        .pictureKind = first.kind
        .current.resize(.width, .height)
        .current.timestamp = first.timestamp
        .modeStride        = .current.columns * 4 + 2
        .modes.resize(cast(u64, ((.current.rows * 4 + 2) * .modeStride)))
        var next = 0's32
        for slice in packet.offsets.count
        {
            .bits   = Bits.open(packet.slice(slice))
            .header = try SliceHeader.read(&.bits, .width, .height)
            if .header.kind != first.kind or
               .header.timestamp != first.timestamp or
               .header.width != .width or
               .header.height != .height or
               .header.start != next do
                fail InvalidFormatError{"RealVideo slices disagree on the picture header or macroblock order"}
            var end = .current.columns * .current.rows
            if slice + 1 < packet.offsets.count
            {
                var look      = Bits.open(packet.slice(slice + 1))
                let following = try SliceHeader.read(&look, .width, .height)
                end = following.start
            }

            if end <= next or end > .current.columns * .current.rows do
                fail InvalidFormatError{"RealVideo slice has no macroblocks or exceeds the picture"}
            Memory.set(.modes.storage(), 255, .modes.count * #sizeof(s32))
            .skipRun = 0
            while next < end
            {
                .blockAt = next
                try .macroblock()
                next += 1
            }
        }

        filterFrame(&.current)
        .current.valid = true
        .current.write(target)
        if first.kind != 3
        {
            .past   = #move .future
            .future = #move .current
        }
    }
}

private func median(a, b, c: s32)->s32 => a + b + c - Math.min(a, Math.min(b, c)) - Math.max(a, Math.max(b, c))
private func hasDirection(kind, direction: s32)->bool => direction == 0 ? (kind == Forward or kind == Bidirectional) : (kind == Backward or kind == Bidirectional)
