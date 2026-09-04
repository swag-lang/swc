#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Sanitizer/SanitizerValue.h"
#include "Compiler/Lexer/SourceCodeRange.h"

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

    // Which slot the POINTER in this register came from, which is a different question from
    // the one above: 'originSlot' says the register holds the value stored in that slot, and
    // a guard narrowing it relies on that. A field or an element address is derived by
    // arithmetic, so it no longer holds the slot's value - and it still addresses the same
    // object, which is what decides whether reading through it touches released memory.
    // Reading a field of a freed object is what a use-after-free almost always looks like,
    // so the two facts have to travel separately.
    bool    hasPointerOriginSlot = false;
    int64_t pointerOriginSlot    = 0;

    bool operator==(const SanitizerRegInfo& o) const
    {
        return value == o.value && hasOriginSlot == o.hasOriginSlot && originSlot == o.originSlot &&
               hasZeroTest == o.hasZeroTest && zeroTestSlot == o.zeroTestSlot && zeroTestTrueIfZero == o.zeroTestTrueIfZero &&
               hasPointerOriginSlot == o.hasPointerOriginSlot && pointerOriginSlot == o.pointerOriginSlot;
    }
};

struct SanitizerMovedRange
{
    uint64_t      size = 0;
    SourceCodeRef origin;
};

// Abstract machine state at one program point: the tracked value of every virtual
// register and simulated local stack slot, plus which register the CPU flags encode a
// comparison of against zero.
struct SanitizerState
{
    std::unordered_map<uint32_t, SanitizerRegInfo> regs;  // key: MicroReg.packed
    std::unordered_map<int64_t, SanitizerValue>    stack; // key: stack slot offset

    // Frame ranges abandoned by a '#move'/'#relocate' (moved-from, not reset), set by a
    // 'SanityInvalidate' marker: key = slot offset. A range is moved-from only when it
    // is on *every* path (join = intersection); any store into the range revalidates
    // it, and calls conservatively clear the whole set. The source identifies the move
    // when every incoming path agrees on it; an ambiguous join keeps the fact without
    // claiming one origin.
    std::unordered_map<int64_t, SanitizerMovedRange> movedFrom;

    // Slots holding a pointer that was handed to a FREEING callee (freesParamsMask):
    // dereferencing that pointer again is a use-after-free, freeing it again a double
    // free. Same discipline as movedFrom: join = intersection, any store that could
    // alias the slot revalidates it, calls conservatively clear the set (the freeing
    // call itself re-marks its arguments afterwards). The value remembers the freeing
    // call so a proven fault can point back to its origin.
    std::unordered_map<int64_t, SourceCodeRef> freedPtrSlots;

    MicroReg flagsSubject = MicroReg::invalid();
};

SWC_END_NAMESPACE();
