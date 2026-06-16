#pragma once
#include "Backend/ABI/CallConv.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;
class MicroUseDefMap;
class MicroSsaState;
class TaskContext;
class Encoder;

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

    // Debug info: the virtual register that holds the local-stack base (the value all local
    // variables are addressed against). Set by the caller before the pass pipeline runs.
    // Register allocation records the physical register it resolves to in debugStackBasePhysReg,
    // and PrologEpilog keeps that in sync across any physical-register remap. Without this the
    // debug records would name a virtual register, which CodeView cannot encode, so every local
    // would be silently dropped and invisible in the debugger.
    MicroReg debugStackBaseVirtualReg = MicroReg::invalid();
    MicroReg debugStackBasePhysReg    = MicroReg::invalid();

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

#if SWC_HAS_STATS
    size_t optimizationInstrRemoved = 0;
    size_t optimizationInstrAdded   = 0;

    // Instruction counts captured at each observable pipeline checkpoint.
    size_t statsInstrInitial          = 0;
    size_t statsInstrAfterStart       = 0;
    size_t statsInstrAfterPreRaOptim  = 0;
    size_t statsInstrAfterRa          = 0;
    size_t statsInstrAfterPostRaSetup = 0;
    size_t statsInstrAfterPostRaOptim = 0;
    size_t statsInstrFinal            = 0;
#endif
};

SWC_END_NAMESPACE();
