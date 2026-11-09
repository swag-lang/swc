//! Format: H.264 software rate-control preparation.
//! Supported: Fractional per-picture budgets, a bounded virtual reservoir, and bounded QP changes.
//! Not supported: A hard output-size guarantee, lookahead, or automatic encoder integration.
//! Role: This private helper estimates the next quantizer from observed picture sizes.
//
#global namespace H264
#global internal

using Core, Core.Errors

// The reservoir is a planning signal, not a cap on encoded pictures. In particular,
// an I_PCM picture can exceed its entire capacity and is still accepted as feedback.
internal struct RateControl
{
    internal
    {
        targetBitsPerSecond: u64
        reservoirBits:       u64
        ticksPerSecond:      u32
        minQp:               u32
        maxQp:               u32
        fullnessBits:        u64
        fractionalBits:      u64
        nextQp:              u32
        lastQp:              u32
        hasObservation:      bool
    }
}

impl RateControl
{
    internal func create(targetBitsPerSecond, reservoirBits: u64, ticksPerSecond,
                minQp, maxQp: u32)->RateControl fail
    {
        if not targetBitsPerSecond or not reservoirBits or not ticksPerSecond or
           minQp > maxQp or maxQp > 51 do
            fail BadParameterError{"H.264 rate control needs a positive rate, reservoir, timescale and QP range"}
        return {targetBitsPerSecond: targetBitsPerSecond,
                reservoirBits: reservoirBits,
                ticksPerSecond: ticksPerSecond,
                minQp: minQp,
                maxQp: maxQp,
                fullnessBits: reservoirBits / 2,
                nextQp: minQp + (maxQp - minQp) / 2}
    }

    // A query has no side effects. Repeated queries before feedback return the same QP.
    // Key pictures and scene cuts request up to two more QP steps, but never bypass
    // the two-step limit relative to the last picture actually encoded.
    internal mtd const chooseQp(isKeyFrame, sceneCut: bool)->u32
    {
        var result = .nextQp
        if isKeyFrame and result < .maxQp do
            result += 1
        if sceneCut and result < .maxQp do
            result += 1
        if .hasObservation and result > .lastQp and result - .lastQp > 2 do
            result = .lastQp + 2
        return result
    }

    // Report a completed picture, in bytes, with its exact duration in timebase ticks.
    // Validate all arithmetic before changing state so a rejected observation can retry.
    internal mtd observe(packetBytes: u64, durationTicks, usedQp: u32) fail
    {
        if not durationTicks or usedQp < .minQp or usedQp > .maxQp or
           (.hasObservation and
            ((usedQp > .lastQp and usedQp - .lastQp > 2) or
             (usedQp < .lastQp and .lastQp - usedQp > 2))) do
            fail BadParameterError{"H.264 rate-control feedback has invalid duration or QP"}
        if packetBytes > Swag.U64.Max / 8 do
            fail OverflowError{"H.264 rate-control picture size overflows bits"}

        let ticks = cast(u64, durationTicks)
        let timebase = cast(u64, .ticksPerSecond)
        let wholeRate = .targetBitsPerSecond / timebase
        if wholeRate > Swag.U64.Max / ticks do
            fail OverflowError{"H.264 rate-control budget overflows"}
        let wholeBudget = wholeRate * ticks
        // Both remainders are smaller than a u32 timebase. Their product plus the
        // carried remainder fits u64 even when durationTicks is U32.Max.
        let fractional = (.targetBitsPerSecond % timebase) * ticks + .fractionalBits
        let extraBudget = fractional / timebase
        if extraBudget > Swag.U64.Max - wholeBudget do
            fail OverflowError{"H.264 rate-control budget overflows"}
        let budget = wholeBudget + extraBudget
        let encodedBits = packetBytes * 8

        var fullness = .fullnessBits
        if encodedBits >= budget
        {
            let deficit = encodedBits - budget
            fullness = deficit >= fullness ? 0 : fullness - deficit
        }
        else
        {
            let surplus = budget - encodedBits
            fullness = surplus >= .reservoirBits - fullness ? .reservoirBits : fullness + surplus
        }

        var next = usedQp
        let quarter = Math.max(1'u64, .reservoirBits / 4)
        if fullness < quarter and next < .maxQp do
            next += Math.min(2'u32, .maxQp - next)
        elif fullness > .reservoirBits - quarter and next > .minQp do
            next -= Math.min(2'u32, next - .minQp)

        .fractionalBits = fractional % timebase
        .fullnessBits = fullness
        .lastQp = usedQp
        .nextQp = next
        .hasObservation = true
    }
}
