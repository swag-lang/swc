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
    CallConvKind          callConvKind            = CallConvKind::Host;
    bool                  preservePersistentRegs  = false;
    bool                  forceFramePointer       = false;
    bool                  microVerify             = false;
    bool                  usesIntReturnRegOnRet   = true;
    bool                  usesFloatReturnRegOnRet = true;

    // Shared use-def map for pre-RA optimization passes.
    // Built once at the start of the optimization loop, invalidated when a pass mutates the IR.
    MicroUseDefMap* useDefMap = nullptr;

    // Shared SSA analysis for pre-RA optimization passes.
    // Built once at the start of the optimization loop, invalidated when a pass mutates the IR.
    MicroSsaState* ssaState = nullptr;

    // Optional fixed-point iteration cap for optimization loops (0 = use level default).
    uint32_t optimizationIterationLimit = 0;
    size_t   printInstrCountBefore      = 0;
    bool     passChanged                = false;

#if SWC_HAS_STATS
    size_t optimizationInstrRemoved = 0;
    size_t optimizationInstrAdded   = 0;

    // Instruction counts captured at the four pipeline checkpoints.
    size_t statsInstrBeforePasses = 0;
    size_t statsInstrAfterOptim   = 0;
    size_t statsInstrAfterRA      = 0;
    size_t statsInstrFinal        = 0;
#endif
};

SWC_END_NAMESPACE();
