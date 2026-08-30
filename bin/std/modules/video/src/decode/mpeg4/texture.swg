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

// The largest magnitude the table codes for one run, clause 7.4.1.3.
//
// The standard prints this as Table B.19 for intra blocks and B.20 for inter ones, but it is not
// separate information: it is the largest level the coefficient table itself holds for that run,
// and the tables here reproduce all four of those tabulations exactly. Deriving it is therefore
// four fewer tables to be right about, and `mpeg4.tables.test.swg` proves the derivation.
func levelMax(inter: bool, last: u32, run: u32)->u32
{
    let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
    let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
    let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

    var result = 0'u32
    for entry in lastOf.count where cast(u32) lastOf[entry] == last and cast(u32) runOf[entry] == run do
        result = Math.max(result, cast(u32) levelOf[entry])
    return result
}

// The largest run the table codes for one magnitude, which the standard prints as Table B.21 and
// B.22. Derived the same way, and proved the same way.
func runMax(inter: bool, last: u32, level: u32)->u32
{
    let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
    let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
    let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

    var result = 0'u32
    var found  = false
    for entry in lastOf.count where cast(u32) lastOf[entry] == last and cast(u32) levelOf[entry] == level
    {
        result = found ? Math.max(result, cast(u32) runOf[entry]) : cast(u32) runOf[entry]
        found  = true
    }

    return result
}

// Reads one coefficient event of a block, clause 7.4.1.
//
// A table entry states a run, a level, and whether the block ends there; the escape code says the
// event is outside what the table holds, in one of three widening forms.
func readCoefficient(reader: *BitReader, inter: bool, result: *Coefficient)->bool
{
    let tree: const [..] s16 = inter ? TcoefInterTree : TcoefIntraTree

    // The escape code shares the code space of the table, so it is recognised before it.
    if (reader.bitPos + cast(u64) TcoefEscapeLen) <= reader.bitEnd
    {
        let mark = reader.bitPos
        if reader.read(TcoefEscapeLen) == TcoefEscapeCod do
            return readEscape(reader, inter, result)
        reader.bitPos = mark
    }

    let entry = reader.decode(tree)
    if entry < 0 do
        return false

    let at = cast(u64) entry
    let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
    let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
    let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

    result.last  = lastOf[at] != 0
    result.run   = cast(u32) runOf[at]
    result.level = cast(s32) levelOf[at]
    if reader.read(1) != 0 do
        result.level = -result.level
    return true
}

// Reads an event the table does not hold, clause 7.4.1.3.
//
// The first form widens the level by the largest the table codes for that run, the second widens
// the run by the largest it codes for that level, and the third states both outright.
private func readEscape(reader: *BitReader, inter: bool, result: *Coefficient)->bool
{
    let tree: const [..] s16 = inter ? TcoefInterTree : TcoefIntraTree

    if reader.read(1) == 0
    {
        let entry = reader.decode(tree)
        if entry < 0 do
            return false
        let at = cast(u64) entry
        let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
        let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
        let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

        result.last  = lastOf[at] != 0
        result.run   = cast(u32) runOf[at]
        result.level = cast(s32) (cast(u32) levelOf[at] + levelMax(inter, cast(u32) lastOf[at], cast(u32) runOf[at]))
        if reader.read(1) != 0 do
            result.level = -result.level
        return true
    }

    if reader.read(1) == 0
    {
        let entry = reader.decode(tree)
        if entry < 0 do
            return false
        let at = cast(u64) entry
        let lastOf:  const [..] u8  = inter ? TcoefInterLast : TcoefIntraLast
        let runOf:   const [..] u8  = inter ? TcoefInterRun : TcoefIntraRun
        let levelOf: const [..] u16 = inter ? TcoefInterLevel : TcoefIntraLevel

        result.last  = lastOf[at] != 0
        result.run   = cast(u32) runOf[at] + runMax(inter, cast(u32) lastOf[at], cast(u32) levelOf[at]) + 1
        result.level = cast(s32) levelOf[at]
        if reader.read(1) != 0 do
            result.level = -result.level
        return true
    }

    // The third form spells the event out, with a marker on each side of the level so the pair
    // cannot look like a start code.
    result.last = reader.read(1) != 0
    result.run  = reader.read(6)
    reader.marker()
    var level = cast(s32) reader.read(12)
    reader.marker()
    if level >= 2048 do
        level -= 4096
    if !level do
        return false
    result.level = level
    return true
}
