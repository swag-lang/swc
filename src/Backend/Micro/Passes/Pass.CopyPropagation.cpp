#include "pch.h"
#include "Backend/Micro/Passes/Pass.CopyPropagation.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Support/Memory/MemoryProfile.h"

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
    SWC_MEM_SCOPE("Backend/MicroLower/CopyProp");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    aliases_.clear();
    aliases_.reserve(64);
    referencedLabels_.clear();
    referencedLabels_.reserve(context.instructions->count());
    MicroPassHelpers::collectReferencedLabels(*context.instructions, *context.operands, referencedLabels_, true);

    MicroOperandStorage& operands = *context.operands;
    for (const MicroInstr& inst : context.instructions->view())
    {
        const MicroInstrOperand* ops = inst.ops(operands);

        if (MicroPassHelpers::shouldClearDataflowStateOnControlFlowBoundary(inst, ops, referencedLabels_))
        {
            aliases_.clear();
            continue;
        }

        const MicroInstrUseDef               useDef = inst.collectUseDef(operands, context.encoder);
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
                // Do not rewrite a use to a register defined by the same instruction.
                // Example: mov tmp, rcx; load rcx, [tmp + 8] must not become [rcx + 8].
                if (microRegSpanContains(useDef.defs, resolvedReg))
                    continue;

                reg                 = resolvedReg;
                context.passChanged = true;
            }
        }

        for (const MicroReg reg : useDef.defs)
            killAliasForDefinition(aliases_, reg);

        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            const MicroReg dstReg = ops[0].reg;
            const MicroReg srcReg = resolveAlias(aliases_, ops[1].reg);
            if (dstReg != srcReg && dstReg.isSameClass(srcReg) && ops[2].opBits == MicroOpBits::B64)
                aliases_[dstReg] = srcReg;
        }

        // Calls clobber registers, invalidating all aliases.
        // Labels and terminators are handled by shouldClearDataflowStateOnControlFlowBoundary above.
        if (useDef.isCall)
            aliases_.clear();
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
