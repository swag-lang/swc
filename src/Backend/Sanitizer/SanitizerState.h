#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Sanitizer/SanitizerValue.h"

SWC_BEGIN_NAMESPACE();

// Per-register information carried along the flow.
struct SanitizerRegInfo
{
    SanitizerValue value;

    // If the register was loaded from a local stack slot, remember which, so a guard
    // testing this register can narrow the slot it came from (in unoptimized IR the
    // guarded block reloads the value from the same slot).
    bool    hasOriginSlot = false;
    int64_t originSlot    = 0;

    // If the register is a boolean produced by a zero test (`setcc` after `cmp x,0`),
    // remember which slot was tested and whether the bool is true when that slot is
    // zero. A branch on the bool then narrows the underlying slot.
    bool    hasZeroTest        = false;
    int64_t zeroTestSlot       = 0;
    bool    zeroTestTrueIfZero = false;

    bool operator==(const SanitizerRegInfo& o) const
    {
        return value == o.value && hasOriginSlot == o.hasOriginSlot && originSlot == o.originSlot &&
               hasZeroTest == o.hasZeroTest && zeroTestSlot == o.zeroTestSlot && zeroTestTrueIfZero == o.zeroTestTrueIfZero;
    }
};

// Abstract machine state at one program point: the tracked value of every virtual
// register and simulated local stack slot, plus which register the CPU flags encode a
// comparison of against zero.
struct SanitizerState
{
    std::unordered_map<uint32_t, SanitizerRegInfo> regs;  // key: MicroReg.packed
    std::unordered_map<int64_t, SanitizerValue>    stack; // key: stack slot offset

    // Frame ranges abandoned by a '#move'/'#relocate' (moved-from, not reset), set by a
    // 'SanityInvalidate' marker: key = slot offset, value = size in bytes. A range is
    // moved-from only when it is on *every* path (join = intersection); any store into
    // the range revalidates it, and calls conservatively clear the whole set.
    std::unordered_map<int64_t, uint64_t> movedFrom;

    MicroReg flagsSubject = MicroReg::invalid();
};

SWC_END_NAMESPACE();
