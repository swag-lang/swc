#include "pch.h"
#include "Backend/Micro/Passes/MicroCopyPropagationPass.h"

// Propagates register aliases created by copy/move instructions.
// Example: mov r2, r1; add r3, r2  ->  add r3, r1.
// Example: mov r2, r1; mov r4, r2  ->  mov r4, r1.
// This shortens copy chains and enables dead-copy elimination.

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroReg resolveAlias(const std::unordered_map<uint32_t, MicroReg>& aliases, MicroReg reg)
    {
        MicroReg current = reg;
        for (uint32_t depth = 0; depth < 32; ++depth)
        {
            const auto it = aliases.find(current.packed);
            if (it == aliases.end())
                return current;
            if (it->second == current)
                return current;
            current = it->second;
        }

        return current;
    }

    void killAliasForDefinition(std::unordered_map<uint32_t, MicroReg>& aliases, MicroReg reg)
    {
        for (auto it = aliases.begin(); it != aliases.end();)
        {
            if (it->first == reg.packed || it->second == reg)
            {
                it = aliases.erase(it);
                continue;
            }

            ++it;
        }
    }

    bool isTerminator(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::JumpTable:
            case MicroInstrOpcode::Ret:
                return true;
            default:
                return false;
        }
    }

    bool isSameRegisterClass(MicroReg leftReg, MicroReg rightReg)
    {
        if (leftReg.isInt() && rightReg.isInt())
            return true;
        if (leftReg.isFloat() && rightReg.isFloat())
            return true;
        if (leftReg.isVirtualInt() && rightReg.isVirtualInt())
            return true;
        if (leftReg.isVirtualFloat() && rightReg.isVirtualFloat())
            return true;
        return false;
    }
}

bool MicroCopyPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                                changed = false;
    std::unordered_map<uint32_t, MicroReg> aliases;
    aliases.reserve(64);

    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
    for (MicroInstr& inst : context.instructions->view())
    {
        if (inst.op == MicroInstrOpcode::Label)
        {
            aliases.clear();
            continue;
        }

        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(operands, refs, context.encoder);
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg || !ref.use || ref.def)
                continue;

            MicroReg& reg         = *SWC_CHECK_NOT_NULL(ref.reg);
            MicroReg  resolvedReg = resolveAlias(aliases, reg);
            if (resolvedReg != reg && isSameRegisterClass(reg, resolvedReg))
            {
                reg     = resolvedReg;
                changed = true;
            }
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        for (MicroReg reg : useDef.defs)
            killAliasForDefinition(aliases, reg);

        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            MicroInstrOperand* instOps = inst.ops(operands);
            const MicroReg     dstReg  = instOps[0].reg;
            const MicroReg     srcReg  = resolveAlias(aliases, instOps[1].reg);
            const bool isIntCopy = (dstReg.isInt() && srcReg.isInt()) || (dstReg.isVirtualInt() && srcReg.isVirtualInt());
            if (dstReg != srcReg && isIntCopy && instOps[2].opBits == MicroOpBits::B64)
                aliases[dstReg.packed] = srcReg;
        }

        if (useDef.isCall || isTerminator(inst))
            aliases.clear();
    }

    return changed;
}

SWC_END_NAMESPACE();
