#include "pch.h"
#include "Backend/Micro/Passes/Pass.CopyPropagation.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"

// Propagates register aliases created by copy/move instructions.
// Example: mov r2, r1; add r3, r2 -> add r3, r1.
// Example: mov r2, r1; mov r4, r2 -> mov r4, r1.
// This shortens copy chains and enables dead-copy elimination.

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroReg resolveAlias(const std::unordered_map<MicroReg, MicroReg>& aliases, MicroReg reg)
    {
        MicroReg current = reg;
        for (uint32_t depth = 0; depth < 32; ++depth)
        {
            const auto it = aliases.find(current);
            if (it == aliases.end())
                return current;
            if (it->second == current)
                return current;
            current = it->second;
        }

        return current;
    }

    void killAliasForDefinition(std::unordered_map<MicroReg, MicroReg>& aliases, MicroReg reg)
    {
        for (auto it = aliases.begin(); it != aliases.end();)
        {
            if (it->first == reg || it->second == reg)
            {
                it = aliases.erase(it);
                continue;
            }

            ++it;
        }
    }

}

Result MicroCopyPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    aliases_.clear();
    aliases_.reserve(64);

    MicroOperandStorage& operands = *context.operands;
    for (const MicroInstr& inst : context.instructions->view())
    {
        if (inst.op == MicroInstrOpcode::Label)
        {
            aliases_.clear();
            continue;
        }

        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(operands, refs, context.encoder);
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg || !ref.use || ref.def)
                continue;

            MicroReg&      reg         = *(ref.reg);
            const MicroReg resolvedReg = resolveAlias(aliases_, reg);
            if (resolvedReg != reg && reg.isSameClass(resolvedReg))
            {
                reg                 = resolvedReg;
                context.passChanged = true;
            }
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        for (const MicroReg reg : useDef.defs)
            killAliasForDefinition(aliases_, reg);

        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            const MicroInstrOperand* instOps = inst.ops(operands);
            const MicroReg           dstReg  = instOps[0].reg;
            const MicroReg           srcReg  = resolveAlias(aliases_, instOps[1].reg);
            if (dstReg != srcReg && dstReg.isSameClass(srcReg) && instOps[2].opBits == MicroOpBits::B64)
                aliases_[dstReg] = srcReg;
        }

        if (MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
            aliases_.clear();
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
