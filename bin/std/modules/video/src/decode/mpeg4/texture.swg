//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns coefficient decoding, the escape forms, and the limits they are stated against.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors

// One coefficient event: how many zeros precede it, its magnitude, and whether it closes the block.
struct Coefficient
{
    run:   u32
    level: s32
    last:  bool
}

// Derive the escape limits of Tables B.19 through B.22 from the coefficient codes.
private struct EscapeLimits
{
    levelByRun: [2, 64] u16
    runByLevel: [2, 64] u8
}

private const IntraLimits: EscapeLimits = #run buildEscapeLimits(TcoefIntraLast, TcoefIntraRun, TcoefIntraLevel)
private const InterLimits: EscapeLimits = #run buildEscapeLimits(TcoefInterLast, TcoefInterRun, TcoefInterLevel)

private func buildEscapeLimits(lasts, runs: const [..] u8, levels: const [..] u16)->EscapeLimits
{
    var result: #returntype
    for index in lasts.count
    {
        let last  = lasts[index]
        let run   = runs[index]
        let level = levels[index]
        result.levelByRun[last, run]   = Math.max(result.levelByRun[last, run], level)
        result.runByLevel[last, level] = Math.max(result.runByLevel[last, level], run)
    }

    return result
}

// Largest level for the given run, clause 7.4.1.3, and zero for an absent key.
func levelMax(inter: bool, last: u32, run: u32)->u32
{
    if last > 1 or run >= 64 do
        return 0
    return inter ? InterLimits.levelByRun[last, run] : IntraLimits.levelByRun[last, run]
}

// Largest run for the given level, clause 7.4.1.3, and zero for an absent key.
func runMax(inter: bool, last: u32, level: u32)->u32
{
    if last > 1 or level >= 64 do
        return 0
    return inter ? InterLimits.runByLevel[last, level] : IntraLimits.runByLevel[last, level]
}

// A nine-bit prefix includes the sign of each code of at most eight bits. The packed entry
// stores the consumed bit count, zero run and last flag below the signed 16-bit level.
private const IntraPrefixes = #run buildCoefficientPrefixes(TcoefIntraLen, TcoefIntraCod, TcoefIntraRun, TcoefIntraLevel, TcoefIntraLast)
private const InterPrefixes = #run buildCoefficientPrefixes(TcoefInterLen, TcoefInterCod, TcoefInterRun, TcoefInterLevel, TcoefInterLast)

private func buildCoefficientPrefixes(lengths: const [..] u8, codes: const [..] u16, runs: const [..] u8, levels: const [..] u16, lasts: const [..] u8)->[512] u32
{
    var result: #returntype
    for index in lengths.count
    {
        let length = cast(u32, lengths[index]) + 1
        if length > 9 do
            continue

        let rest      = 9 - length
        let magnitude = cast(s32, levels[index])
        let fields    = length | (cast(u32, runs[index]) << 4) | (cast(u32, lasts[index]) << 10)
        for sign in 2'u32
        {
            let level = sign ? -magnitude : magnitude
            let entry = fields | ((cast #bit(u32, level) & 0xFFFF) << 16)
            let first = ((cast(u32, codes[index]) << 1) | sign) << rest
            for suffix in 1'u32 << rest do
                result[first + suffix] = entry
        }
    }

    return result
}

#[Swag.Inline]
func coefficientPrefixes(inter: bool)->const [*] u32 => inter ? &InterPrefixes[0] : &IntraPrefixes[0]

// The short path consumes the complete event, so it needs no fallible call or separate sign read.
#[Swag.Inline]
func readCoefficientPrefix(reader: *BitReader, prefixes: const [*] u32, result: *Coefficient)->bool
{
    let at = reader.bitPos
    if at + 16 > reader.bitEnd do
        return false

    let data = unwrap reader.data + (at >> 3)
    let word = cast(u32, Swag.byteSwap(cast(const [*] u16, data)[0]))
    let bits = (word >> (7 - cast(u32, at & 7))) & 511
    let code = prefixes[bits]
    if not code do
        return false

    reader.bitPos += code & 15
    result.last   = (code & 0x400) != 0
    result.run    = (code >> 4) & 63
    result.level  = cast #bit(s32, code) >> 16
    return true
}

// Reads a longer coefficient code or an escape, clause 7.4.1, also handling a short input tail.
func readCoefficient(reader: *BitReader, inter: bool, result: *Coefficient)->bool fail
{
    if reader.bitPos + TcoefEscapeLen <= reader.bitEnd
    {
        let mark = reader.bitPos
        if reader.read(TcoefEscapeLen) == TcoefEscapeCod do
            return try readEscape(reader, inter, result)
        reader.bitPos = mark
    }

    let tree: const [..] s16 = inter ? TcoefInterTree : TcoefIntraTree
    let entry = reader.decode(tree)
    if entry < 0 do
        return false

    let at = cast(u64, entry)
    let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
    let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
    let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

    result.last  = lastOf[at] != 0
    result.run   = cast(u32, runOf[at])
    result.level = cast(s32, levelOf[at])
    if reader.read(1) != 0 do
        result.level = -result.level
    return true
}

// Reads an event the table does not hold, clause 7.4.1.3.
//
// The first form widens the level by the largest the table codes for that run, the second widens
// the run by the largest it codes for that level, and the third states both outright.
private func readEscape(reader: *BitReader, inter: bool, result: *Coefficient)->bool fail
{
    let tree: const [..] s16 = inter ? TcoefInterTree : TcoefIntraTree

    if reader.read(1) == 0
    {
        let entry = reader.decode(tree)
        if entry < 0 do
            return false
        let at = cast(u64, entry)
        let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
        let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
        let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

        result.last  = lastOf[at] != 0
        result.run   = cast(u32, runOf[at])
        result.level = cast(s32, (cast(u32, levelOf[at]) + levelMax(inter, cast(u32, lastOf[at]), cast(u32, runOf[at]))))
        if reader.read(1) != 0 do
            result.level = -result.level
        return true
    }

    if reader.read(1) == 0
    {
        let entry = reader.decode(tree)
        if entry < 0 do
            return false
        let at = cast(u64, entry)
        let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
        let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
        let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

        result.last  = lastOf[at] != 0
        result.run   = cast(u32, runOf[at]) + runMax(inter, cast(u32, lastOf[at]), cast(u32, levelOf[at])) + 1
        result.level = cast(s32, levelOf[at])
        if reader.read(1) != 0 do
            result.level = -result.level
        return true
    }

    // The third form spells the event out, with a marker on each side of the level so the pair
    // cannot look like a start code.
    result.last = reader.read(1) != 0
    result.run  = reader.read(6)
    try reader.marker()
    var level = cast(s32, reader.read(12))
    try reader.marker()
    if level >= 2048 do
        level -= 4096
    if not level do
        return false
    result.level = level
    return true
}
