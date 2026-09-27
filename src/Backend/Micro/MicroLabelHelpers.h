#pragma once
#include "Backend/Micro/MicroInstr.h"

#include <limits>

SWC_BEGIN_NAMESPACE();

namespace MicroLabelHelpers
{
    inline bool tryGetLabelId(uint32_t& outLabelId, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        outLabelId = 0;
        if (inst.op != MicroInstrOpcode::Label || !ops || ops[0].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[0].valueU64);
        return true;
    }

    inline bool tryGetJumpTargetLabelId(uint32_t& outLabelId, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        outLabelId = 0;
        if (inst.op != MicroInstrOpcode::JumpCond || !ops || ops[2].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[2].valueU64);
        return true;
    }
}

SWC_END_NAMESPACE();
