#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Sanitizer/SanitizerValue.h"
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

// One place inside an object the frame does not hold: the object is named by where its
// POINTER lives - a frame slot, or a register the function defines once - and the place
// by the offset from it. Two accesses through two different registers reloaded from the
// same variable name the same location, which is what a release and the use that follows
// it are written as.
struct SanitizerLocation
{
    bool     fromSlot   = false;
    int64_t  slot       = 0;
    uint32_t basePacked = 0;
    int64_t  offset     = 0;

    auto operator<=>(const SanitizerLocation&) const = default;
};

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

    // The nearest VIRTUAL register this value was copied from. A call's arguments are
    // moved into the convention's physical registers, which the call then clobbers, so a
    // release has to name the register the value actually lives in.
    bool     hasOriginReg = false;
    MicroReg originReg;

    // The place this value was loaded FROM when it was not a frame slot. A pointer a heap
    // object owns lives there and nowhere else, so 'object.buffer' released and read again
    // - the commonest shape a real use-after-free has - is nameable exactly here.
    bool              hasOriginLocation = false;
    SanitizerLocation originLocation;

    // The place this register's ADDRESS designates, which is a different question from
    // the one above: the codegen forms a field's address first and reads through it
    // second, so without this the two accesses to one field would name two registers and
    // nothing would connect them.
    bool              hasAddressLocation = false;
    SanitizerLocation addressLocation;

    // The pointer this register holds was handed to a freeing callee. A register is a
    // value: only a redefinition changes it, so the fact travels with the copies the
    // codegen makes and outlives the calls in between. This is what names a released
    // PARAMETER, which has no frame slot of its own to be keyed on.
    bool          releasedPointer = false;
    SourceCodeRef releasedOrigin;

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
               hasPointerOriginSlot == o.hasPointerOriginSlot && pointerOriginSlot == o.pointerOriginSlot &&
               hasOriginReg == o.hasOriginReg && originReg == o.originReg &&
               releasedPointer == o.releasedPointer &&
               releasedOrigin.srcViewRef == o.releasedOrigin.srcViewRef && releasedOrigin.tokRef == o.releasedOrigin.tokRef &&
               hasOriginLocation == o.hasOriginLocation && originLocation == o.originLocation &&
               hasAddressLocation == o.hasAddressLocation && addressLocation == o.addressLocation;
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

    // Proven slot copies: the key holds the very value the mapped slot holds. Only slots
    // inside a declared local whose address is never formed take part, so nothing but an
    // explicit store to one of the two can break the equality - neither a callee nor a
    // store through a pointer can reach them. Releasing one member releases the whole
    // class, which is what turns 'let b = a' followed by a release of 'a' from a miss
    // into a proof. Same join as the sets above: intersection.
    std::unordered_map<int64_t, int64_t> aliasPtrSlots;

    // Declared locals whose address has left the engine's sight: handed to a callee,
    // stored, or folded into a value it no longer recognizes as an address. A later call
    // can write through it, so the two sets above keep nothing about such an object past
    // one. Unlike every other fact here this one is a MAY fact - the join is a union -
    // and an address the codegen only ever uses as the base of an access never enters it,
    // which is what leaves an ordinary local protected. Keyed by the start of the
    // variable's storage; a compiler temporary is never protected in the first place.
    std::unordered_set<int64_t> escapedFrameObjects;

    // Released pointers that did not live in the frame: keyed by the base register the
    // access went through and the offset from it. A callee can write through any pointer
    // it is handed, so unlike the frame facts these keep nothing across a call - which is
    // enough, because a release and the use that follows it sit in one body.
    std::map<SanitizerLocation, SourceCodeRef> freedPtrLocations;

    MicroReg flagsSubject = MicroReg::invalid();
};

SWC_END_NAMESPACE();
