#pragma once
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    using MicroPassHelpers::RegTouch;

    inline RegTouch regTouch(const Context& ctx, const MicroInstr& inst, MicroReg reg)
    {
        return MicroPassHelpers::regTouch(inst, *ctx.operands, reg, ctx.encoder);
    }
}

SWC_END_NAMESPACE();
