#pragma once
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace MicroInstrInfo
{
    bool isTerminatorInstruction(const MicroInstr& inst);
    bool isUnconditionalJumpInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool hasObservableSideEffect(const MicroInstr& inst);
    bool isLocalDataflowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef);
}

SWC_END_NAMESPACE();
