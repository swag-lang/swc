#pragma once
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;
class MicroUseDefMap;
class MicroSsaState;
class TaskContext;
class Encoder;
class SymbolFunction;

struct MicroPassContext
{
    MicroPassContext() = default;

    // Selected call convention drives register classes, stack alignment, and saved regs.
    Encoder*              encoder                 = nullptr;
    TaskContext*          taskContext             = nullptr;
    MicroBuilder*         builder                 = nullptr;
    MicroStorage*         instructions            = nullptr;
    MicroOperandStorage*  operands                = nullptr;
    std::span<const Utf8> passPrintOptions        = {};
    CallConvKind          callConvKind            = CallConvKind::Swag;
    bool                  preservePersistentRegs  = false;
    bool                  forceFramePointer       = false;
    bool                  validateMicro           = false;
    bool                  usesIntReturnRegOnRet   = true;
    bool                  usesFloatReturnRegOnRet = true;

    // The function's effective runtime-safety mask (build-config default combined with
    // any `#[Swag.Safety(...)]` overrides). The static sanitizer runs the checks whose
    // safety guard is set here, so it honours per-scope safety, not just the global
    // build configuration. 0 (the default, used for compiler-generated code) disables it.
    uint16_t sanitizerSafetyMask = 0;

    // The function being lowered, for sanitizer checks that need its signature (return
    // type nullability, ...). Null for compiler-generated code.
    const SymbolFunction* sanitizerFunction = nullptr;

    // Debug info: the virtual register that holds the local-stack base (the value all local
    // variables are addressed against). Set by the caller before the pass pipeline runs.
    // Register allocation records the physical register it resolves to in debugStackBasePhysReg,
    // and PrologEpilog keeps that in sync across any physical-register remap. Without this the
    // debug records would name a virtual register, which CodeView cannot encode, so every local
    // would be silently dropped and invisible in the debugger.
    MicroReg debugStackBaseVirtualReg = MicroReg::invalid();
    MicroReg debugStackBasePhysReg    = MicroReg::invalid();

    // The byte range of the frame register allocation gave its own spill slots, as the emitted
    // code addresses it. Those slots are the compiler's: no source object overlaps one and no
    // pointer can be made to reach one, which is what lets a post-RA pass reason about them in a
    // function whose other frame objects escape. Empty (lo >= hi) when nothing spilled.
    uint64_t spillAreaLo = std::numeric_limits<uint64_t>::max();
    uint64_t spillAreaHi = 0;

    // Shared use-def map for pre-RA optimization passes.
    // Built once at the start of the optimization loop, invalidated when a pass mutates the IR.
    MicroUseDefMap* useDefMap = nullptr;

    // Shared SSA analysis for pre-RA optimization passes.
    // Built lazily by MicroSsaState::ensureFor and invalidated when a pass mutates the IR.
    MicroSsaState* ssaState = nullptr;

    // Optional fixed-point iteration cap for optimization loops (0 = use level default).
    uint32_t optimizationIterationLimit = 0;
    size_t   printInstrCountBefore      = 0;
    bool     passChanged                = false;

    // True during the first sweep of a bounded optimization loop. Post-RA
    // forwarding transforms (copy/const forwarding) are only sound on the
    // pristine IR straight out of register allocation, where the spill-reload
    // and ABI-marshalling shapes they target live; they must not re-run on
    // already-cleaned-up IR. Erase/DCE cleanups have no such restriction.
    bool isFirstOptimizationSweep = true;

    // True during the first sweep of the legalize/allocate loop, i.e. while
    // register allocation is still assigning the whole function. Legalization
    // of the allocator's own output introduces fresh virtual scratch registers,
    // which sends the loop round again; that later sweep allocates a handful of
    // values into a function whose registers are already committed, and it has
    // no record of the whole-range reservations the first sweep made. Only the
    // first sweep may hand a value a register for its entire live range.
    bool isFirstAllocationSweep = true;

    // Physical registers the first allocation sweep handed to a value for its
    // entire live range. A later sweep allocates into a function whose
    // registers are already committed, and it rebuilds its state from scratch,
    // so nothing else remembers those reservations: without this list it can
    // hand a scratch value a register that still holds a live one, and no
    // repair path can notice — the value it displaces has no spill home to be
    // restored from. Reset with the rest of the pipeline state.
    SmallVector<MicroReg> globalReservedRegs;
};

SWC_END_NAMESPACE();
