#include "pch.h"
#include "Backend/Micro/Passes/MicroPeepholePass.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroOptimization.h"

// Runs local late cleanups after reg alloc/legalize.
// Example: mov r1, r1 -> <remove>.
// Example: add r1, 0 / or r1, 0 -> <remove>.
// Example: and r1, all_ones -> <remove>.
// These strips leftover no-ops before final emission.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct PeepholeCursor
    {
        Ref                      instRef;
        MicroInstr*              inst;
        const MicroInstrOperand* ops;
        MicroStorage::Iterator   nextIt;
        MicroStorage::Iterator   endIt;
    };

    enum class PeepholeRuleTarget : uint8_t
    {
        AnyInstruction,
        LoadRegReg,
    };

    using PeepholeRuleMatchFn   = bool (*)(const MicroPassContext& context, const PeepholeCursor& cursor);
    using PeepholeRuleRewriteFn = bool (*)(const MicroPassContext& context, const PeepholeCursor& cursor);

    struct PeepholeRule
    {
        std::string_view      name;
        PeepholeRuleTarget    target;
        PeepholeRuleMatchFn   match;
        PeepholeRuleRewriteFn rewrite;
    };

    bool isCopyDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg)
    {
        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&                    scanInst = *scanIt;
            const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);

            bool hasUse = false;
            bool hasDef = false;
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg || *SWC_CHECK_NOT_NULL(ref.reg) != reg)
                    continue;

                hasUse |= ref.use;
                hasDef |= ref.def;
            }

            if (hasUse)
                return false;

            if (hasDef)
                return true;

            if (scanInst.op == MicroInstrOpcode::Ret)
                return true;

            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
                return false;
        }

        return true;
    }

    bool tryForwardCopyIntoNextBinarySource(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
    {
        if (!ops || nextIt == endIt)
            return false;

        const MicroInstr&  nextInst = *nextIt;
        MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        if (nextInst.op != MicroInstrOpcode::OpBinaryRegReg || !nextOps)
            return false;

        const MicroReg copyDstReg = ops[0].reg;
        const MicroReg copySrcReg = ops[1].reg;
        if (nextOps[1].reg != copyDstReg)
            return false;
        if (nextOps[0].reg == copyDstReg)
            return false;
        if (ops[2].opBits != nextOps[2].opBits)
            return false;
        if (!MicroOptimization::isSameRegisterClass(copyDstReg, copySrcReg))
            return false;
        if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, copyDstReg))
            return false;

        nextOps[1].reg = copySrcReg;
        SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
        return true;
    }

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

    bool tryCoalesceCopyInstruction(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, MicroStorage::Iterator scanBegin, const MicroStorage::Iterator& endIt)
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

    bool matchForwardCopyIntoNextBinarySource(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        if (!cursor.ops || cursor.nextIt == cursor.endIt)
            return false;

        const MicroInstr&        nextInst = *cursor.nextIt;
        const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        return nextInst.op == MicroInstrOpcode::OpBinaryRegReg && nextOps;
    }

    bool rewriteForwardCopyIntoNextBinarySource(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryForwardCopyIntoNextBinarySource(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    bool matchCoalesceCopyInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(context);
        return cursor.ops != nullptr;
    }

    bool rewriteCoalesceCopyInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryCoalesceCopyInstruction(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    bool matchRemoveOverwrittenCopy(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        if (!cursor.ops || cursor.nextIt == cursor.endIt)
            return false;

        const MicroInstr&        nextInst = *cursor.nextIt;
        const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        return nextInst.op == MicroInstrOpcode::LoadRegReg && nextOps;
    }

    bool rewriteRemoveOverwrittenCopy(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryRemoveOverwrittenCopy(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    bool matchRemoveNoOpInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(context);
        return MicroOptimization::isNoOpEncoderInstruction(*SWC_CHECK_NOT_NULL(cursor.inst), cursor.ops);
    }

    bool rewriteRemoveNoOpInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryRemoveNoOpInstruction(context, cursor.instRef, *SWC_CHECK_NOT_NULL(cursor.inst), cursor.ops);
    }

    bool isRuleApplicable(const PeepholeRule& rule, const PeepholeCursor& cursor)
    {
        switch (rule.target)
        {
            case PeepholeRuleTarget::AnyInstruction:
                return true;
            case PeepholeRuleTarget::LoadRegReg:
                return SWC_CHECK_NOT_NULL(cursor.inst)->op == MicroInstrOpcode::LoadRegReg;
            default:
                return false;
        }
    }

    const std::array<PeepholeRule, 4>& peepholeRules()
    {
        static constexpr std::array<PeepholeRule, 4> RULES = {{
            {"forward_copy_into_next_binary_source", PeepholeRuleTarget::LoadRegReg, matchForwardCopyIntoNextBinarySource, rewriteForwardCopyIntoNextBinarySource},
            {"coalesce_copy_instruction", PeepholeRuleTarget::LoadRegReg, matchCoalesceCopyInstruction, rewriteCoalesceCopyInstruction},
            {"remove_overwritten_copy", PeepholeRuleTarget::LoadRegReg, matchRemoveOverwrittenCopy, rewriteRemoveOverwrittenCopy},
            {"remove_no_op_instruction", PeepholeRuleTarget::AnyInstruction, matchRemoveNoOpInstruction, rewriteRemoveNoOpInstruction},
        }};

        return RULES;
    }

    bool tryApplyRule(const MicroPassContext& context, const PeepholeRule& rule, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(rule.name);
        if (!isRuleApplicable(rule, cursor))
            return false;

        if (!SWC_CHECK_NOT_NULL(rule.match)(context, cursor))
            return false;

        return SWC_CHECK_NOT_NULL(rule.rewrite)(context, cursor);
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
        PeepholeCursor cursor;
        cursor.instRef = instRef;
        cursor.inst    = &inst;
        cursor.ops     = ops;
        cursor.nextIt  = it;
        cursor.endIt   = view.end();

        bool appliedRule = false;
        for (const PeepholeRule& rule : peepholeRules())
        {
            if (!tryApplyRule(context, rule, cursor))
                continue;

            changed     = true;
            appliedRule = true;
            break;
        }

        if (appliedRule)
            continue;
    }

    return changed;
}

SWC_END_NAMESPACE();
