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
    // guarded block reloads the pointer from the same slot).
    bool    hasOriginSlot = false;
    int64_t originSlot    = 0;

    // If the register is a boolean produced by a null test (`setcc` after `cmp x,0`),
    // remember which slot was tested and whether the bool is true when that slot is
    // null. A branch on the bool then narrows the underlying pointer's slot.
    bool    hasNullTest        = false;
    int64_t nullTestSlot       = 0;
    bool    nullTestTrueIfNull = false;

    bool operator==(const SanitizerRegInfo& o) const
    {
        return value == o.value && hasOriginSlot == o.hasOriginSlot && originSlot == o.originSlot &&
               hasNullTest == o.hasNullTest && nullTestSlot == o.nullTestSlot && nullTestTrueIfNull == o.nullTestTrueIfNull;
    }
};

// Abstract machine state at one program point: the tracked value of every virtual
// register and simulated local stack slot, plus which register the CPU flags encode a
// comparison of against zero.
struct SanitizerState
{
    std::unordered_map<uint32_t, SanitizerRegInfo> regs;  // key: MicroReg.packed
    std::unordered_map<int64_t, SanitizerValue>    stack; // key: stack slot offset
    MicroReg                                       flagsSubject = MicroReg::invalid();
};

SWC_END_NAMESPACE();
