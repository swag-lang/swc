#include "pch.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        bool isSelfCopyNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg || !ops)
                return false;

            if (ops[0].reg != ops[1].reg)
                return false;

            // "mov eax, eax" is not a no-op on x64 because it clears the upper
            // 32 bits of the parent register. Keep those copies intact.
            if (ops[0].reg.isAnyInt() && ops[2].opBits == MicroOpBits::B32)
                return false;

            return true;
        }
    }

    bool Context::claimAll(std::initializer_list<MicroInstrRef> refs)
    {
        for (const MicroInstrRef ref : refs)
            if (isClaimed(ref))
                return false;

        for (const MicroInstrRef ref : refs)
            claimed.insert(ref.get());
        return true;
    }

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.op == MicroInstrOpcode::Nop || isSelfCopyNoEffect(inst, ops);
    }

    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (!info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
            return false;

        if ((inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm) &&
            ops &&
            ops[0].cpuCond == MicroCond::Unconditional)
            return false;

        return true;
    }

    bool isRedundantFallthroughJumpToNextLabel(const Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::JumpCond || !ops)
            return false;

        const uint64_t targetLabel = ops[2].valueU64;
        for (MicroInstrRef scanRef = ctx.nextRef(ref); scanRef.isValid(); scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;

            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);
            if (scanInst->op == MicroInstrOpcode::Label)
            {
                if (scanOps && scanOps[0].valueU64 == targetLabel)
                    return true;

                continue;
            }

            if (isTriviallyErasableNoEffect(*scanInst, scanOps))
                continue;

            return false;
        }

        return false;
    }

    // Mirrors the "dead after consumer" scan used by the forwarding rules.
    // Fallthrough-jumps-to-next-label count as no-ops because a sibling pattern
    // in this same pass erases them.
    bool regIsDeadAfter(const Context& ctx, const MicroInstrRef fromRef, const MicroReg reg)
    {
        constexpr int K_MAX_LIVENESS_WINDOW = 32;

        MicroInstrRef cur = ctx.nextRef(fromRef);
        for (int step = 0; step < K_MAX_LIVENESS_WINDOW && cur.isValid(); ++step, cur = ctx.nextRef(cur))
        {
            const MicroInstr* inst = ctx.instruction(cur);
            if (!inst)
                return false;

            const MicroInstrUseDef useDef = inst->collectUseDef(*ctx.operands, ctx.encoder);
            for (const MicroReg used : useDef.uses)
            {
                if (used == reg)
                    return false;
            }
            for (const MicroReg defined : useDef.defs)
            {
                if (defined == reg)
                    return true;
            }

            const MicroInstrOperand* ops = inst->ops(*ctx.operands);
            if (isRedundantFallthroughJumpToNextLabel(ctx, cur, *inst, ops))
                continue;

            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
