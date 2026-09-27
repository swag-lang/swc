#pragma once
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    inline bool regInList(std::span<const MicroReg> list, MicroReg reg)
    {
        for (const MicroReg r : list)
            if (r == reg)
                return true;
        return false;
    }

    struct RegTouch
    {
        bool use = false;
        bool def = false;
    };

    inline RegTouch regTouch(const Context& ctx, const MicroInstr& inst, MicroReg reg)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            (ctx.encoder && info.flags.has(MicroInstrFlagsE::EncoderRegUseDef)))
        {
            const MicroInstrUseDef useDef = inst.collectUseDef(*ctx.operands, ctx.encoder);
            return {regInList(useDef.uses.span(), reg), regInList(useDef.defs.span(), reg)};
        }

        RegTouch touch;
        if (const MicroInstrOperand* ops = inst.ops(*ctx.operands))
        {
            const auto modes = info.resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] == MicroInstrRegMode::None || ops[i].reg != reg)
                    continue;
                touch.use |= modes[i] == MicroInstrRegMode::Use || modes[i] == MicroInstrRegMode::UseDef;
                touch.def |= modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef;
            }
        }
        return touch;
    }
}

SWC_END_NAMESPACE();
