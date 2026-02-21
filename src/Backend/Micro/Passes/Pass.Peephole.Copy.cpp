#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool forwardCopyIntoNextBinarySource(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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
            if (!copyDstReg.isSameClass(copySrcReg))
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

        bool forwardCopyIntoNextCompareSource(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&  nextInst = *nextIt;
            MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
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

        bool foldCopyTwinLoadMemReuse(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator firstLoadIt = nextIt;
            if (firstLoadIt == endIt)
                return false;

            const MicroStorage::Iterator secondLoadIt = std::next(firstLoadIt);
            if (secondLoadIt == endIt)
                return false;

            MicroInstr& firstLoadInst = *firstLoadIt;
            if (firstLoadInst.op != MicroInstrOpcode::LoadRegMem)
                return false;

            MicroInstr& secondLoadInst = *secondLoadIt;
            if (secondLoadInst.op != MicroInstrOpcode::LoadRegMem)
                return false;

            MicroInstrOperand* firstLoadOps  = firstLoadInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            MicroInstrOperand* secondLoadOps = secondLoadInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!firstLoadOps || !secondLoadOps)
                return false;

            const MicroReg copiedBaseReg = ops[0].reg;
            const MicroReg baseSrcReg    = ops[1].reg;
            if (!copiedBaseReg.isSameClass(baseSrcReg))
                return false;

            if (firstLoadOps[1].reg != copiedBaseReg || secondLoadOps[1].reg != copiedBaseReg)
                return false;
            if (firstLoadOps[0].reg != baseSrcReg)
                return false;
            if (firstLoadOps[0].reg == secondLoadOps[0].reg)
                return false;
            if (!firstLoadOps[0].reg.isSameClass(secondLoadOps[0].reg))
                return false;
            if (firstLoadOps[2].opBits != secondLoadOps[2].opBits)
                return false;
            if (firstLoadOps[3].valueU64 != secondLoadOps[3].valueU64)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(secondLoadIt), endIt, copiedBaseReg))
                return false;

            const std::array<MicroInstrOperand, 4> originalFirstLoadOps = {firstLoadOps[0], firstLoadOps[1], firstLoadOps[2], firstLoadOps[3]};
            const std::array<MicroInstrOperand, 4> originalSecondLoadOps = {secondLoadOps[0], secondLoadOps[1], secondLoadOps[2], secondLoadOps[3]};
            const MicroInstrOpcode                 originalSecondLoadOp   = secondLoadInst.op;

            firstLoadOps[1].reg = baseSrcReg;
            if (MicroOptimization::violatesEncoderConformance(context, firstLoadInst, firstLoadOps))
            {
                for (uint32_t i = 0; i < 4; ++i)
                    firstLoadOps[i] = originalFirstLoadOps[i];
                return false;
            }

            const MicroReg copiedValueReg = firstLoadOps[0].reg;
            secondLoadInst.op             = MicroInstrOpcode::LoadRegReg;
            secondLoadOps[0].reg          = originalSecondLoadOps[0].reg;
            secondLoadOps[1].reg          = copiedValueReg;
            secondLoadOps[2].opBits       = originalSecondLoadOps[2].opBits;
            secondLoadOps[3].valueU64     = 0;
            if (MicroOptimization::violatesEncoderConformance(context, secondLoadInst, secondLoadOps))
            {
                for (uint32_t i = 0; i < 4; ++i)
                    firstLoadOps[i] = originalFirstLoadOps[i];
                secondLoadInst.op = originalSecondLoadOp;
                for (uint32_t i = 0; i < 4; ++i)
                    secondLoadOps[i] = originalSecondLoadOps[i];
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldCopyOpCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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
            if (!tmpReg.isSameClass(srcReg))
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

        bool foldCopyUnaryCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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
            if (!tmpReg.isSameClass(srcReg))
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
                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
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
                            mutableReg                 = srcReg;
                            if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                            {
                                mutableReg  = originalReg;
                                canCoalesce = false;
                                break;
                            }

                            mutableReg        = originalReg;
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
                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
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

        bool coalesceCopyInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef   = cursor.instRef;
            const MicroInstrOperand*     ops       = cursor.ops;
            const MicroStorage::Iterator scanBegin = cursor.nextIt;
            const MicroStorage::Iterator endIt     = cursor.endIt;
            if (!ops)
                return false;

            const MicroReg dstReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (dstReg == srcReg || !dstReg.isSameClass(srcReg))
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

        bool removeOverwrittenCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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

        bool foldCopyBackWithPreviousOp(const MicroPassContext& context, const Cursor& cursor)
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

            const MicroReg origReg     = cursor.ops[0].reg;
            const MicroReg tmpReg      = cursor.ops[1].reg;
            if (!origReg.isSameClass(tmpReg))
                return false;

            if (prevOpOps[0].reg != tmpReg)
                return false;
            if (prevCopyOps[0].reg != tmpReg || prevCopyOps[1].reg != origReg)
                return false;
            if (prevOpOps[1].reg == origReg)
                return false;
            if (cursor.ops[2].opBits != prevOpOps[2].opBits || cursor.ops[2].opBits != prevCopyOps[2].opBits)
                return false;

            MicroInstrOperand* mutablePrevOpOps = prevOpInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!mutablePrevOpOps)
                return false;

            const MicroReg originalReg = prevOpOps[0].reg;
            mutablePrevOpOps[0].reg    = origReg;
            if (MicroOptimization::violatesEncoderConformance(context, prevOpInst, mutablePrevOpOps))
            {
                mutablePrevOpOps[0].reg = originalReg;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(prevCopyIt.current);
            SWC_CHECK_NOT_NULL(context.instructions)->erase(cursor.instRef);
            return true;
        }
    }

    void appendCopyRules(RuleList& outRules)
    {
        // Rule: forward_copy_into_next_binary_source
        // Purpose: forward copied source register into the next binary operation source.
        // Example: mov r8, r11; and r5, r8 -> and r5, r11
        outRules.push_back({RuleTarget::LoadRegReg, forwardCopyIntoNextBinarySource});

        // Rule: forward_copy_into_next_compare_source
        // Purpose: forward copied source register into next compare.
        // Example: mov r8, r11; cmp r8, 0 -> cmp r11, 0
        outRules.push_back({RuleTarget::LoadRegReg, forwardCopyIntoNextCompareSource});

        // Rule: fold_copy_twin_load_mem_reuse
        // Purpose: reuse first identical memory load result and remove copied-base register.
        // Example: mov r10, rdx; mov rdx, [r10]; mov r9, [r10] -> mov rdx, [rdx]; mov r9, rdx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyTwinLoadMemReuse});

        // Rule: fold_copy_op_copy_back
        // Purpose: fold copy-to-temp + binary-op + copy-back into direct binary-op on a source.
        // Example: mov r8, r11; and r8, rdx; mov r11, r8 -> and r11, rdx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyOpCopyBack});

        // Rule: fold_copy_unary_copy_back
        // Purpose: fold copy-to-temp + unary-op + copy-back into direct unary-op on source.
        // Example: mov r8, r11; neg r8; mov r11, r8 -> neg r11
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyUnaryCopyBack});

        // Rule: fold_copy_back_with_previous_op
        // Purpose: same fold as above, detected from trailing copy-back instruction.
        // Example: mov r8, r11; xor r8, rdx; mov r11, r8 -> xor r11, rdx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyBackWithPreviousOp});

        // Rule: coalesce_copy_instruction
        // Purpose: rewrite downstream uses of copy destination to copy source and remove copy.
        // Example: mov r8, r11; add r9, r8; or r10, r8 -> add r9, r11; or r10, r11
        outRules.push_back({RuleTarget::LoadRegReg, coalesceCopyInstruction});

        // Rule: remove_overwritten_copy
        // Purpose: remove a copy when the destination is immediately overwritten by another copy.
        // Example: mov r8, r11; mov r8, rdx -> mov r8, rdx
        outRules.push_back({RuleTarget::LoadRegReg, removeOverwrittenCopy});
    }
}

SWC_END_NAMESPACE();
