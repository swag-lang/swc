#include "pch.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    namespace
    {
        constexpr uint32_t K_MAX_STORE_SCAN_WINDOW = 32;

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

        bool instructionMayReadMemory(const MicroInstr& inst)
        {
            const MicroInstrDef& info = MicroInstr::info(inst.op);
            if (info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                !info.flags.has(MicroInstrFlagsE::WritesMemory) &&
                inst.op != MicroInstrOpcode::LoadAddrRegMem)
                return true;

            return inst.op == MicroInstrOpcode::LoadAmcRegMem ||
                   inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem ||
                   inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem;
        }

        bool isSameStoreLocation(const MicroInstrOperand* lhs, const MicroInstrOperand* rhs)
        {
            return lhs && rhs &&
                   lhs[0].reg == rhs[0].reg &&
                   lhs[2].opBits == rhs[2].opBits &&
                   lhs[3].valueU64 == rhs[3].valueU64;
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

    bool Context::isPrivateFrameBase(const MicroReg reg) const
    {
        return reg.isValid() &&
               (reg == stackPointer || reg == framePointer || reg == localStackBase);
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

    bool tryEraseOverwrittenStore(Context& ctx, const MicroInstrRef storeRef, const MicroInstr& storeInst)
    {
        // Frame homes are private to the current function. A later exact store
        // therefore kills this one when no instruction in between can observe
        // memory and no control-flow edge can enter the scanned sequence.
        const MicroInstrOperand* storeOps = storeInst.ops(*ctx.operands);
        if (storeInst.op != MicroInstrOpcode::LoadMemReg || !storeOps)
            return false;

        const MicroReg baseReg = storeOps[0].reg;
        if (!ctx.isPrivateFrameBase(baseReg))
            return false;

        MicroInstrRef  scanRef = ctx.nextRef(storeRef);
        for (uint32_t step = 0; step < K_MAX_STORE_SCAN_WINDOW && scanRef.isValid(); ++step, scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;
            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);

            if (scanInst->op == MicroInstrOpcode::LoadMemReg && isSameStoreLocation(storeOps, scanOps))
            {
                if (!ctx.claimAll({storeRef}))
                    return false;
                ctx.emitErase(storeRef);
                return true;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            if (scanInst->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) ||
                scanInst->op == MicroInstrOpcode::Push ||
                scanInst->op == MicroInstrOpcode::Pop ||
                instructionMayReadMemory(*scanInst))
                return false;

            const MicroInstrUseDef useDef = scanInst->collectUseDef(*ctx.operands, ctx.encoder);
            if (std::ranges::find(useDef.defs, baseReg) != useDef.defs.end())
                return false;
        }

        return false;
    }

    bool tryEraseRedundantStoreReload(Context& ctx, const MicroInstrRef storeRef, const MicroInstr& storeInst)
    {
        // The stored physical register still contains the same value when it
        // has not been redefined. Conditional jumps are safe here: the reload
        // only belongs to their fallthrough path, while labels stop the scan.
        const MicroInstrOperand* storeOps = storeInst.ops(*ctx.operands);
        if (storeInst.op != MicroInstrOpcode::LoadMemReg || !storeOps)
            return false;

        const MicroReg baseReg   = storeOps[0].reg;
        const MicroReg sourceReg = storeOps[1].reg;
        if (!ctx.isPrivateFrameBase(baseReg))
            return false;

        MicroInstrRef  scanRef   = ctx.nextRef(storeRef);
        for (uint32_t step = 0; step < K_MAX_STORE_SCAN_WINDOW && scanRef.isValid(); ++step, scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;
            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);

            if (scanInst->op == MicroInstrOpcode::LoadRegMem &&
                scanOps &&
                scanOps[0].reg == sourceReg &&
                scanOps[1].reg == baseReg &&
                scanOps[2].opBits == storeOps[2].opBits &&
                scanOps[3].valueU64 == storeOps[3].valueU64)
            {
                if (!ctx.claimAll({scanRef}))
                    return false;
                ctx.emitErase(scanRef);
                return true;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            const bool conditionalJump = info.flags.has(MicroInstrFlagsE::JumpInstruction) &&
                                         info.flags.has(MicroInstrFlagsE::ConditionalJump);
            if (scanInst->op == MicroInstrOpcode::Label ||
                (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) && !conditionalJump) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) ||
                scanInst->op == MicroInstrOpcode::Push ||
                scanInst->op == MicroInstrOpcode::Pop ||
                instructionMayReadMemory(*scanInst))
                return false;

            if (info.flags.has(MicroInstrFlagsE::JumpInstruction) && !conditionalJump)
                return false;

            const MicroInstrUseDef useDef = scanInst->collectUseDef(*ctx.operands, ctx.encoder);
            if (std::ranges::find(useDef.defs, baseReg) != useDef.defs.end() ||
                std::ranges::find(useDef.defs, sourceReg) != useDef.defs.end())
                return false;
        }

        return false;
    }

    bool tryForwardStoredValueToReload(Context& ctx, const MicroInstrRef storeRef, const MicroInstr& storeInst)
    {
        // A register copy preserves the exact partial-register semantics of an
        // equal-width reload. Unlike the dead-reload rule above, intervening
        // memory reads are harmless; writes can alias the frame slot and stop
        // the scan conservatively.
        const MicroInstrOperand* storeOps = storeInst.ops(*ctx.operands);
        if (storeInst.op != MicroInstrOpcode::LoadMemReg || !storeOps)
            return false;

        const MicroReg baseReg   = storeOps[0].reg;
        const MicroReg sourceReg = storeOps[1].reg;
        if (!ctx.isPrivateFrameBase(baseReg))
            return false;

        MicroInstrRef scanRef = ctx.nextRef(storeRef);
        for (uint32_t step = 0; step < K_MAX_STORE_SCAN_WINDOW && scanRef.isValid(); ++step, scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;
            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);

            if (scanInst->op == MicroInstrOpcode::LoadRegMem &&
                scanOps &&
                scanOps[1].reg == baseReg &&
                scanOps[2].opBits == storeOps[2].opBits &&
                scanOps[3].valueU64 == storeOps[3].valueU64)
            {
                if (!ctx.claimAll({scanRef}))
                    return false;

                MicroInstrOperand newOps[3] = {};
                newOps[0].reg               = scanOps[0].reg;
                newOps[1].reg               = sourceReg;
                newOps[2].opBits            = storeOps[2].opBits;
                ctx.emitRewrite(scanRef, MicroInstrOpcode::LoadRegReg, std::span{newOps, 3});
                return true;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            const bool conditionalJump = info.flags.has(MicroInstrFlagsE::JumpInstruction) &&
                                         info.flags.has(MicroInstrFlagsE::ConditionalJump);
            if (scanInst->op == MicroInstrOpcode::Label ||
                (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) && !conditionalJump) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) ||
                scanInst->op == MicroInstrOpcode::Push ||
                scanInst->op == MicroInstrOpcode::Pop)
                return false;

            if (info.flags.has(MicroInstrFlagsE::JumpInstruction) && !conditionalJump)
                return false;

            const MicroInstrUseDef useDef = scanInst->collectUseDef(*ctx.operands, ctx.encoder);
            if (std::ranges::find(useDef.defs, baseReg) != useDef.defs.end() ||
                std::ranges::find(useDef.defs, sourceReg) != useDef.defs.end())
                return false;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
