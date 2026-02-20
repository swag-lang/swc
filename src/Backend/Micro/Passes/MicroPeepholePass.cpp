#include "pch.h"
#include "Backend/Micro/Passes/MicroPeepholePass.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/Passes/MicroOptimization.h"

// Runs local late cleanups after regalloc/legalize.
// Example: mov r1, r1           -> <remove>.
// Example: add r1, 0 / or r1, 0 -> <remove>.
// Example: and r1, all_ones     -> <remove>.
// This strips leftover no-ops before final emission.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool analyzeCopyCoalescing(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg dstReg, MicroReg srcReg, bool& outSawMutation)
    {
        bool canCoalesce       = true;
        bool sawReplaceableUse = false;
        bool seenMutation      = false;

        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&      scanInst = *scanIt;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
                break;

            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg)
                    continue;

                const MicroReg reg = *SWC_CHECK_NOT_NULL(ref.reg);
                if (reg == srcReg)
                {
                    if (seenMutation || ref.def)
                    {
                        canCoalesce = false;
                        break;
                    }
                }

                if (reg == dstReg)
                {
                    if (ref.def && !ref.use)
                    {
                        canCoalesce = false;
                        break;
                    }

                    if (ref.use && ref.def)
                    {
                        if (seenMutation)
                        {
                            canCoalesce = false;
                            break;
                        }

                        seenMutation      = true;
                        sawReplaceableUse = true;
                        continue;
                    }

                    if (ref.use)
                        sawReplaceableUse = true;
                }
            }

            if (!canCoalesce)
                break;
        }

        outSawMutation = seenMutation;
        return canCoalesce && seenMutation && sawReplaceableUse;
    }

    bool applyCopyCoalescing(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg dstReg, MicroReg srcReg)
    {
        bool changed = false;

        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&      scanInst = *scanIt;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
                break;

            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg)
                    continue;

                MicroReg& reg = *SWC_CHECK_NOT_NULL(ref.reg);
                if (reg != dstReg || !ref.use)
                    continue;

                reg     = srcReg;
                changed = true;
            }
        }

        return changed;
    }

    bool tryCoalesceCopyInstruction(MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, MicroStorage::Iterator scanBegin, const MicroStorage::Iterator& endIt)
    {
        if (!ops)
            return false;

        const MicroReg dstReg = ops[0].reg;
        const MicroReg srcReg = ops[1].reg;
        if (dstReg == srcReg || !MicroOptimization::isSameRegisterClass(dstReg, srcReg))
            return false;

        bool sawMutation = false;
        if (!analyzeCopyCoalescing(context, scanBegin, endIt, dstReg, srcReg, sawMutation))
            return false;

        if (!applyCopyCoalescing(context, scanBegin, endIt, dstReg, srcReg))
            return false;

        if (sawMutation)
            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);

        return true;
    }

    bool tryRemoveOverwrittenCopy(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
    {
        if (!ops || nextIt == endIt)
            return false;

        const MicroInstr&        nextInst = *nextIt;
        const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        if (nextInst.op != MicroInstrOpcode::LoadRegReg || !nextOps)
            return false;

        if (ops[0].reg != nextOps[0].reg || ops[2].opBits != nextOps[2].opBits)
            return false;

        SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
        return true;
    }

    bool tryRemoveNoOpInstruction(const MicroPassContext& context, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!MicroOptimization::isNoOpEncoderInstruction(inst, ops))
            return false;

        SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
        return true;
    }
}

bool MicroPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    bool changed = false;

    const MicroStorage::View view = context.instructions->view();
    for (auto it = view.begin(); it != view.end();)
    {
        const Ref                instRef = it.current;
        MicroInstr&              inst    = *it;
        const MicroInstrOperand* ops     = inst.ops(*context.operands);
        ++it;

        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            if (tryCoalesceCopyInstruction(context, instRef, ops, it, view.end()))
            {
                changed = true;
                continue;
            }

            if (tryRemoveOverwrittenCopy(context, instRef, ops, it, view.end()))
            {
                changed = true;
                continue;
            }
        }

        if (tryRemoveNoOpInstruction(context, instRef, inst, ops))
            changed = true;
    }

    return changed;
}

SWC_END_NAMESPACE();
