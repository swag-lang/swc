#include "pch.h"
#include "Backend/Micro/Passes/MicroPeepholePass.Private.h"
#include "Backend/Micro/MicroOptimization.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
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

            const MicroReg originalSrcReg = nextOps[1].reg;
            nextOps[1].reg                = copySrcReg;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextOps[1].reg = originalSrcReg;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool tryForwardCopyIntoNextCompareSource(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&  nextInst = *nextIt;
            MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!MicroOptimization::isSameRegisterClass(copyDstReg, copySrcReg))
                return false;

            bool replacesOperand = false;

            if (nextInst.op == MicroInstrOpcode::CmpRegReg)
            {
                if (ops[2].opBits != nextOps[2].opBits)
                    return false;

                if (nextOps[0].reg == copyDstReg)
                {
                    nextOps[0].reg  = copySrcReg;
                    replacesOperand = true;
                }

                if (nextOps[1].reg == copyDstReg)
                {
                    nextOps[1].reg  = copySrcReg;
                    replacesOperand = true;
                }
            }
            else if (nextInst.op == MicroInstrOpcode::CmpRegImm)
            {
                if (ops[2].opBits != nextOps[1].opBits)
                    return false;

                if (nextOps[0].reg == copyDstReg)
                {
                    nextOps[0].reg  = copySrcReg;
                    replacesOperand = true;
                }
            }
            else if (nextInst.op == MicroInstrOpcode::CmpRegZero)
            {
                if (ops[2].opBits != nextOps[1].opBits)
                    return false;

                if (nextOps[0].reg == copyDstReg)
                {
                    nextOps[0].reg  = copySrcReg;
                    replacesOperand = true;
                }
            }
            else
            {
                return false;
            }

            if (!replacesOperand)
                return false;

            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, copyDstReg))
                return false;

            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
                return false;

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool tryFoldCopyOpCopyBack(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator opIt       = nextIt;
            const MicroStorage::Iterator copyBackIt = std::next(opIt);
            if (copyBackIt == endIt)
                return false;

            const MicroInstr&        opInst = *opIt;
            const MicroInstrOperand* opOps  = opInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (opInst.op != MicroInstrOpcode::OpBinaryRegReg || !opOps)
                return false;

            const MicroInstr&        copyBackInst = *copyBackIt;
            const MicroInstrOperand* copyBackOps  = copyBackInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (copyBackInst.op != MicroInstrOpcode::LoadRegReg || !copyBackOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (!MicroOptimization::isSameRegisterClass(tmpReg, srcReg))
                return false;
            if (opOps[0].reg != tmpReg)
                return false;
            if (copyBackOps[0].reg != srcReg || copyBackOps[1].reg != tmpReg)
                return false;
            if (ops[2].opBits != opOps[2].opBits || ops[2].opBits != copyBackOps[2].opBits)
                return false;
            if (opOps[1].reg == srcReg)
                return false;

            MicroInstrOperand* mutableOpOps   = opInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            const MicroReg     originalDstReg = mutableOpOps[0].reg;
            mutableOpOps[0].reg               = srcReg;
            if (MicroOptimization::violatesEncoderConformance(context, opInst, mutableOpOps))
            {
                mutableOpOps[0].reg = originalDstReg;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            SWC_CHECK_NOT_NULL(context.instructions)->erase(copyBackIt.current);
            return true;
        }

        bool tryFoldCopyUnaryCopyBack(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator unaryIt    = nextIt;
            const MicroStorage::Iterator copyBackIt = std::next(unaryIt);
            if (copyBackIt == endIt)
                return false;

            const MicroInstr& unaryInst = *unaryIt;
            if (unaryInst.op != MicroInstrOpcode::OpUnaryReg)
                return false;

            MicroInstrOperand* unaryOps = unaryInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!unaryOps)
                return false;

            const MicroInstr&        copyBackInst = *copyBackIt;
            const MicroInstrOperand* copyBackOps  = copyBackInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (copyBackInst.op != MicroInstrOpcode::LoadRegReg || !copyBackOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (!MicroOptimization::isSameRegisterClass(tmpReg, srcReg))
                return false;

            if (unaryOps[0].reg != tmpReg)
                return false;
            if (copyBackOps[0].reg != srcReg || copyBackOps[1].reg != tmpReg)
                return false;

            if (ops[2].opBits != unaryOps[1].opBits || ops[2].opBits != copyBackOps[2].opBits)
                return false;

            const MicroReg originalDstReg = unaryOps[0].reg;
            unaryOps[0].reg               = srcReg;
            if (MicroOptimization::violatesEncoderConformance(context, unaryInst, unaryOps))
            {
                unaryOps[0].reg = originalDstReg;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            SWC_CHECK_NOT_NULL(context.instructions)->erase(copyBackIt.current);
            return true;
        }

        bool analyzeCopyCoalescing(const MicroPassContext& context, bool& outSawMutation, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg dstReg, MicroReg srcReg)
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

                const MicroInstrOperand* scanOps = scanInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                if (scanInst.op == MicroInstrOpcode::LoadRegReg && scanOps && scanOps[0].reg == srcReg && scanOps[1].reg == dstReg)
                {
                    canCoalesce = false;
                    break;
                }

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
                            seenMutation      = true;
                            sawReplaceableUse = true;
                            continue;
                        }

                        if (ref.use)
                        {
                            MicroReg&      mutableReg  = *SWC_CHECK_NOT_NULL(ref.reg);
                            const MicroReg originalReg = mutableReg;
                            mutableReg                  = srcReg;
                            if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                            {
                                mutableReg  = originalReg;
                                canCoalesce = false;
                                break;
                            }

                            mutableReg      = originalReg;
                            sawReplaceableUse = true;
                        }
                    }
                }

                if (!canCoalesce)
                    break;
            }

            outSawMutation = seenMutation;
            return canCoalesce && sawReplaceableUse;
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
            if (!analyzeCopyCoalescing(context, sawMutation, scanBegin, endIt, dstReg, srcReg))
                return false;

            if (!applyCopyCoalescing(context, scanBegin, endIt, dstReg, srcReg))
                return false;

            SWC_UNUSED(sawMutation);
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

        bool matchForwardCopyIntoNextBinarySource(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroInstr&        nextInst = *cursor.nextIt;
            const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            return nextInst.op == MicroInstrOpcode::OpBinaryRegReg && nextOps;
        }

        bool rewriteForwardCopyIntoNextBinarySource(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryForwardCopyIntoNextBinarySource(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchForwardCopyIntoNextCompareSource(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroInstr& nextInst = *cursor.nextIt;
            switch (nextInst.op)
            {
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::CmpRegImm:
                case MicroInstrOpcode::CmpRegZero:
                    break;
                default:
                    return false;
            }

            return nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands)) != nullptr;
        }

        bool rewriteForwardCopyIntoNextCompareSource(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryForwardCopyIntoNextCompareSource(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldCopyOpCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroStorage::Iterator opIt       = cursor.nextIt;
            const MicroStorage::Iterator copyBackIt = std::next(opIt);
            if (copyBackIt == cursor.endIt)
                return false;

            const MicroInstr&        opInst = *opIt;
            const MicroInstrOperand* opOps  = opInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (opInst.op != MicroInstrOpcode::OpBinaryRegReg || !opOps)
                return false;

            const MicroInstr&        copyBackInst = *copyBackIt;
            const MicroInstrOperand* copyBackOps  = copyBackInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (copyBackInst.op != MicroInstrOpcode::LoadRegReg || !copyBackOps)
                return false;

            const MicroReg tmpReg = cursor.ops[0].reg;
            const MicroReg srcReg = cursor.ops[1].reg;
            if (opOps[0].reg != tmpReg)
                return false;
            if (copyBackOps[0].reg != srcReg || copyBackOps[1].reg != tmpReg)
                return false;
            if (opOps[1].reg == srcReg)
                return false;
            if (cursor.ops[2].opBits != opOps[2].opBits || cursor.ops[2].opBits != copyBackOps[2].opBits)
                return false;

            return MicroOptimization::isSameRegisterClass(tmpReg, srcReg);
        }

        bool rewriteFoldCopyOpCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldCopyOpCopyBack(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldCopyUnaryCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroStorage::Iterator unaryIt    = cursor.nextIt;
            const MicroStorage::Iterator copyBackIt = std::next(unaryIt);
            if (copyBackIt == cursor.endIt)
                return false;

            const MicroInstr& unaryInst = *unaryIt;
            if (unaryInst.op != MicroInstrOpcode::OpUnaryReg)
                return false;

            const MicroInstrOperand* unaryOps = unaryInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!unaryOps)
                return false;

            const MicroInstr&        copyBackInst = *copyBackIt;
            const MicroInstrOperand* copyBackOps  = copyBackInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (copyBackInst.op != MicroInstrOpcode::LoadRegReg || !copyBackOps)
                return false;

            const MicroReg tmpReg = cursor.ops[0].reg;
            const MicroReg srcReg = cursor.ops[1].reg;
            if (!MicroOptimization::isSameRegisterClass(tmpReg, srcReg))
                return false;

            if (unaryOps[0].reg != tmpReg)
                return false;
            if (copyBackOps[0].reg != srcReg || copyBackOps[1].reg != tmpReg)
                return false;
            if (cursor.ops[2].opBits != unaryOps[1].opBits || cursor.ops[2].opBits != copyBackOps[2].opBits)
                return false;

            return true;
        }

        bool rewriteFoldCopyUnaryCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldCopyUnaryCopyBack(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldCopyBackWithPreviousOp(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops)
                return false;

            MicroStorage::Iterator currentIt = cursor.nextIt;
            --currentIt;
            if (currentIt.current == INVALID_REF)
                return false;

            MicroStorage::Iterator prevOpIt = currentIt;
            --prevOpIt;
            if (prevOpIt.current == INVALID_REF)
                return false;

            MicroStorage::Iterator prevCopyIt = prevOpIt;
            --prevCopyIt;
            if (prevCopyIt.current == INVALID_REF)
                return false;

            const MicroInstr&        prevOpInst = *prevOpIt;
            const MicroInstrOperand* prevOpOps  = prevOpInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (prevOpInst.op != MicroInstrOpcode::OpBinaryRegReg || !prevOpOps)
                return false;

            const MicroInstr&        prevCopyInst = *prevCopyIt;
            const MicroInstrOperand* prevCopyOps  = prevCopyInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (prevCopyInst.op != MicroInstrOpcode::LoadRegReg || !prevCopyOps)
                return false;

            const MicroReg origReg = cursor.ops[0].reg;
            const MicroReg tmpReg  = cursor.ops[1].reg;
            if (!MicroOptimization::isSameRegisterClass(origReg, tmpReg))
                return false;

            if (prevOpOps[0].reg != tmpReg)
                return false;
            if (prevCopyOps[0].reg != tmpReg || prevCopyOps[1].reg != origReg)
                return false;
            if (prevOpOps[1].reg == origReg)
                return false;
            if (cursor.ops[2].opBits != prevOpOps[2].opBits || cursor.ops[2].opBits != prevCopyOps[2].opBits)
                return false;

            SWC_UNUSED(context);
            return true;
        }

        bool rewriteFoldCopyBackWithPreviousOp(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops)
                return false;

            MicroStorage::Iterator currentIt = cursor.nextIt;
            --currentIt;
            if (currentIt.current == INVALID_REF)
                return false;

            MicroStorage::Iterator prevOpIt = currentIt;
            --prevOpIt;
            if (prevOpIt.current == INVALID_REF)
                return false;

            MicroStorage::Iterator prevCopyIt = prevOpIt;
            --prevCopyIt;
            if (prevCopyIt.current == INVALID_REF)
                return false;

            MicroInstr&        prevOpInst = *prevOpIt;
            MicroInstrOperand* prevOpOps  = prevOpInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!prevOpOps)
                return false;

            const MicroReg origReg     = cursor.ops[0].reg;
            const MicroReg originalReg = prevOpOps[0].reg;
            prevOpOps[0].reg           = origReg;
            if (MicroOptimization::violatesEncoderConformance(context, prevOpInst, prevOpOps))
            {
                prevOpOps[0].reg = originalReg;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(prevCopyIt.current);
            SWC_CHECK_NOT_NULL(context.instructions)->erase(cursor.instRef);
            return true;
        }

        bool matchCoalesceCopyInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.ops != nullptr;
        }

        bool rewriteCoalesceCopyInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryCoalesceCopyInstruction(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchRemoveOverwrittenCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroInstr&        nextInst = *cursor.nextIt;
            const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            SWC_UNUSED(context);
            return nextInst.op == MicroInstrOpcode::LoadRegReg && nextOps;
        }

        bool rewriteRemoveOverwrittenCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryRemoveOverwrittenCopy(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }
    }

    void appendCopyRules(RuleList& outRules)
    {
        outRules.push_back({"forward_copy_into_next_binary_source", RuleTarget::LoadRegReg, matchForwardCopyIntoNextBinarySource, rewriteForwardCopyIntoNextBinarySource});
        outRules.push_back({"forward_copy_into_next_compare_source", RuleTarget::LoadRegReg, matchForwardCopyIntoNextCompareSource, rewriteForwardCopyIntoNextCompareSource});
        outRules.push_back({"fold_copy_op_copy_back", RuleTarget::LoadRegReg, matchFoldCopyOpCopyBack, rewriteFoldCopyOpCopyBack});
        outRules.push_back({"fold_copy_unary_copy_back", RuleTarget::LoadRegReg, matchFoldCopyUnaryCopyBack, rewriteFoldCopyUnaryCopyBack});
        outRules.push_back({"fold_copy_back_with_previous_op", RuleTarget::LoadRegReg, matchFoldCopyBackWithPreviousOp, rewriteFoldCopyBackWithPreviousOp});
        outRules.push_back({"coalesce_copy_instruction", RuleTarget::LoadRegReg, matchCoalesceCopyInstruction, rewriteCoalesceCopyInstruction});
        outRules.push_back({"remove_overwritten_copy", RuleTarget::LoadRegReg, matchRemoveOverwrittenCopy, rewriteRemoveOverwrittenCopy});
    }
}

SWC_END_NAMESPACE();
