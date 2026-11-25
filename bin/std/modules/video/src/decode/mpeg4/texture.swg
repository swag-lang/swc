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

// Each short prefix carries its bit length and table index. The normative codes are
// prefix-free, so expanding a short code over its suffixes cannot hide a longer one.
private const IntraPrefixes: [256] u16 = #run buildCoefficientPrefixes(TcoefIntraLen, TcoefIntraCod)
private const InterPrefixes: [256] u16 = #run buildCoefficientPrefixes(TcoefInterLen, TcoefInterCod)

private func buildCoefficientPrefixes(lengths: const [..] u8, codes: const [..] u16)->[256] u16
{
    var result: #returntype
    for index in lengths.count
    {
        let length = cast(u32, lengths[index])
        if length > 8 do
            continue

        let rest  = 8 - length
        let first = cast(u32, codes[index]) << rest
        let entry = cast(u16, (length << 8) | cast(u32, index + 1))
        for suffix in 1'u32 << rest do
            result[first + suffix] = entry
    }

    return result
}

// Reads a byte of lookahead from two bytes that the caller knows are available.
#[Swag.Inline]
private func peekCoefficientPrefix(reader: const *BitReader)->u32
{
    let at   = reader.bitPos
    let data = unwrap reader.data
    let byte = at >> 3
    let word = (cast(u32, data[byte]) << 8) | cast(u32, data[byte + 1])
    return (word >> (8 - cast(u32, at & 7))) & 255
}

// Reads one coefficient event of a block, clause 7.4.1.
//
// A table entry states a run, a level, and whether the block ends there; the escape code says the
// event is outside what the table holds, in one of three widening forms.
func readCoefficient(reader: *BitReader, inter: bool, result: *Coefficient)->bool fail
{
    var entry = -1
    if reader.bitPos + 15 <= reader.bitEnd
    {
        let lookahead = peekCoefficientPrefix(reader)
        let code      = inter ? InterPrefixes[lookahead] : IntraPrefixes[lookahead]
        if code
        {
            reader.bitPos += code >> 8
            entry         = cast(s32, (code & 255)) - 1
        }
    }

    if entry < 0
    {
        // The escape code shares the code space of the table, so recognize it before
        // walking the tree. This path also handles the short input at the end.
        if reader.bitPos + TcoefEscapeLen <= reader.bitEnd
        {
            let mark = reader.bitPos
            if reader.read(TcoefEscapeLen) == TcoefEscapeCod do
                return try readEscape(reader, inter, result)
            reader.bitPos = mark
        }

        let tree: const [..] s16 = inter ? TcoefInterTree : TcoefIntraTree
        entry = reader.decode(tree)
        if entry < 0 do
            return false
    }

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
