#pragma once
#include "Backend/ABI/CallConv.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;
class TaskContext;
class Encoder;

struct MicroPassContext
{
    MicroPassContext() = default;

    // Selected call convention drives register classes, stack alignment, and saved regs.
    Encoder*              encoder                = nullptr;
    TaskContext*          taskContext            = nullptr;
    MicroBuilder*         builder                = nullptr;
    MicroStorage*         instructions           = nullptr;
    MicroOperandStorage*  operands               = nullptr;
    std::span<const Utf8> passPrintOptions       = {};
    CallConvKind          callConvKind           = CallConvKind::Host;
    bool                  preservePersistentRegs = false;

    // Optional fixed-point iteration cap for optimization loops (0 = use level default).
    uint32_t optimizationIterationLimit = 0;
    size_t   printInstrCountBefore      = 0;
    bool     passChanged                = false;

#if SWC_HAS_STATS
    size_t optimizationInstrRemoved = 0;
    size_t optimizationInstrAdded   = 0;
#endif
};

SWC_END_NAMESPACE();
