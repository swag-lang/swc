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

        const MicroReg originalSrcReg = nextOps[1].reg;
        nextOps[1].reg = copySrcReg;
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

        MicroInstrOperand* mutableOpOps = opInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        const MicroReg     originalDstReg = mutableOpOps[0].reg;
        mutableOpOps[0].reg                = srcReg;
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
                        seenMutation = true;
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
        if (!analyzeCopyCoalescing(context, scanBegin, endIt, dstReg, srcReg, sawMutation))
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

    bool tryRemoveNoOpInstruction(const MicroPassContext& context, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!MicroOptimization::isNoOpEncoderInstruction(inst, ops))
            return false;

        SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
        return true;
    }

    bool tryCanonicalizeCmpRegImmZero(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(context);
        if (!cursor.ops)
            return false;

        if (cursor.inst->op != MicroInstrOpcode::CmpRegImm)
            return false;
        if (cursor.ops[2].valueU64 != 0)
            return false;

        cursor.inst->op = MicroInstrOpcode::CmpRegZero;
        return true;
    }

    bool tryFoldSetCondZeroExtCopy(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
    {
        if (!ops || nextIt == endIt)
            return false;

        const MicroStorage::Iterator zeroExtIt = nextIt;
        const MicroStorage::Iterator copyIt    = std::next(zeroExtIt);
        if (copyIt == endIt)
            return false;

        const MicroInstr& zeroExtInst = *zeroExtIt;
        if (zeroExtInst.op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;

        MicroInstrOperand* zeroExtOps = zeroExtInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        if (!zeroExtOps)
            return false;

        const MicroInstr& copyInst = *copyIt;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
        if (!copyOps)
            return false;

        const MicroReg tmpReg = ops[0].reg;
        if (zeroExtOps[0].reg != tmpReg || zeroExtOps[1].reg != tmpReg)
            return false;
        if (zeroExtOps[2].opBits != MicroOpBits::B32 || zeroExtOps[3].opBits != MicroOpBits::B8)
            return false;
        if (copyOps[1].reg != tmpReg)
            return false;
        if (!MicroOptimization::isSameRegisterClass(copyOps[0].reg, tmpReg))
            return false;

        if (!isCopyDeadAfterInstruction(context, std::next(copyIt), endIt, tmpReg))
            return false;

        const MicroReg dstReg = copyOps[0].reg;

        MicroInstr*        setCondInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(instRef);
        MicroInstrOperand* setCondOps  = setCondInst ? setCondInst->ops(*SWC_CHECK_NOT_NULL(context.operands)) : nullptr;
        if (!setCondOps)
            return false;

        const MicroReg originalSetCondReg = setCondOps[0].reg;
        setCondOps[0].reg                 = dstReg;
        if (MicroOptimization::violatesEncoderConformance(context, *setCondInst, setCondOps))
        {
            setCondOps[0].reg = originalSetCondReg;
            return false;
        }

        const MicroReg originalZeroExtDst = zeroExtOps[0].reg;
        const MicroReg originalZeroExtSrc = zeroExtOps[1].reg;
        zeroExtOps[0].reg                 = dstReg;
        zeroExtOps[1].reg                 = dstReg;
        if (MicroOptimization::violatesEncoderConformance(context, zeroExtInst, zeroExtOps))
        {
            setCondOps[0].reg = originalSetCondReg;
            zeroExtOps[0].reg = originalZeroExtDst;
            zeroExtOps[1].reg = originalZeroExtSrc;
            return false;
        }

        SWC_CHECK_NOT_NULL(context.instructions)->erase(copyIt.current);
        return true;
    }

    // Rule: forward_copy_into_next_binary_source
    // Purpose: remove a copy when the very next binary op only reads the copied temp.
    // Example:
    //   mov r8, r11
    //   and r5, r8
    // becomes:
    //   and r5, r11
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

    // Rule: forward_copy_into_next_compare_source
    // Purpose: remove a copy when the very next compare only reads the copied temp.
    // Example:
    //   mov r8, r11
    //   cmp r8, 0
    // becomes:
    //   cmp r11, 0
    bool matchForwardCopyIntoNextCompareSource(const MicroPassContext& context, const PeepholeCursor& cursor)
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

    bool rewriteForwardCopyIntoNextCompareSource(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryForwardCopyIntoNextCompareSource(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    // Rule: fold_copy_op_copy_back
    // Purpose: fold "copy to tmp + mutate tmp + copy back" into a direct mutation.
    // Example:
    //   mov r8, r11
    //   and r8, rdx
    //   mov r11, r8
    // becomes:
    //   and r11, rdx
    bool matchFoldCopyOpCopyBack(const MicroPassContext& context, const PeepholeCursor& cursor)
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

    bool rewriteFoldCopyOpCopyBack(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryFoldCopyOpCopyBack(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    // Rule: fold_copy_unary_copy_back
    // Purpose: fold "copy to tmp + unary mutate tmp + copy back" into a direct unary mutation.
    // Example:
    //   mov r8, r11
    //   neg r8
    //   mov r11, r8
    // becomes:
    //   neg r11
    bool matchFoldCopyUnaryCopyBack(const MicroPassContext& context, const PeepholeCursor& cursor)
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

    bool rewriteFoldCopyUnaryCopyBack(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryFoldCopyUnaryCopyBack(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    // Rule: fold_copy_back_with_previous_op
    // Purpose: the same fold as above, but anchored from the trailing copy-back instruction.
    // Example:
    //   mov r8, r11
    //   xor r8, rdx
    //   mov r11, r8
    // becomes:
    //   xor r11, rdx
    bool matchFoldCopyBackWithPreviousOp(const MicroPassContext& context, const PeepholeCursor& cursor)
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

        return true;
    }

    bool rewriteFoldCopyBackWithPreviousOp(const MicroPassContext& context, const PeepholeCursor& cursor)
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

        const MicroReg origReg = cursor.ops[0].reg;
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

    // Rule: coalesce_copy_instruction
    // Purpose: replace downstream uses of copy destination by source, then erase the copy.
    // Example:
    //   mov r8, r11
    //   add r9, r8
    //   or  r10, r8
    // becomes:
    //   add r9, r11
    //   or  r10, r11
    bool matchCoalesceCopyInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(context);
        return cursor.ops != nullptr;
    }

    bool rewriteCoalesceCopyInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryCoalesceCopyInstruction(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
    }

    // Rule: remove_overwritten_copy
    // Purpose: delete a copy when the same destination is immediately overwritten.
    // Example:
    //   mov r8, r11
    //   mov r8, rdx
    // becomes:
    //   mov r8, rdx
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

    // Rule: remove_no_op_instruction
    // Purpose: erase encoder-level no-op instructions.
    // Example:
    //   mov r8, r8
    // or:
    //   add r8, 0
    // becomes:
    //   <removed>
    bool matchRemoveNoOpInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(context);
        return MicroOptimization::isNoOpEncoderInstruction(*SWC_CHECK_NOT_NULL(cursor.inst), cursor.ops);
    }

    bool rewriteRemoveNoOpInstruction(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryRemoveNoOpInstruction(context, cursor.instRef, *SWC_CHECK_NOT_NULL(cursor.inst), cursor.ops);
    }

    // Rule: canonicalize_cmp_reg_imm_zero
    // Purpose: canonicalize compare-against-zero to dedicated opcode.
    // Example:
    //   cmp r11, 0
    // becomes:
    //   cmp_zero r11
    bool matchCanonicalizeCmpRegImmZero(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        SWC_UNUSED(context);
        return cursor.inst->op == MicroInstrOpcode::CmpRegImm && cursor.ops && cursor.ops[2].valueU64 == 0;
    }

    bool rewriteCanonicalizeCmpRegImmZero(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryCanonicalizeCmpRegImmZero(context, cursor);
    }

    // Rule: fold_setcond_zeroext_copy
    // Purpose: route setcc and its zero-extend directly to the final destination register.
    // Example:
    //   setcc r10
    //   zero_extend r10
    //   mov rax, r10
    // becomes:
    //   setcc rax
    //   zero_extend rax
    bool matchFoldSetCondZeroExtCopy(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        if (cursor.inst->op != MicroInstrOpcode::SetCondReg || !cursor.ops || cursor.nextIt == cursor.endIt)
            return false;

        const MicroStorage::Iterator zeroExtIt = cursor.nextIt;
        const MicroStorage::Iterator copyIt    = std::next(zeroExtIt);
        if (copyIt == cursor.endIt)
            return false;

        const MicroInstr& zeroExtInst = *zeroExtIt;
        if (zeroExtInst.op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;

        const MicroInstr& copyInst = *copyIt;
        return copyInst.op == MicroInstrOpcode::LoadRegReg;
    }

    bool rewriteFoldSetCondZeroExtCopy(const MicroPassContext& context, const PeepholeCursor& cursor)
    {
        return tryFoldSetCondZeroExtCopy(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
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

    const std::array<PeepholeRule, 10>& peepholeRules()
    {
        static constexpr std::array<PeepholeRule, 10> RULES = {{
            {"forward_copy_into_next_binary_source", PeepholeRuleTarget::LoadRegReg, matchForwardCopyIntoNextBinarySource, rewriteForwardCopyIntoNextBinarySource},
            {"forward_copy_into_next_compare_source", PeepholeRuleTarget::LoadRegReg, matchForwardCopyIntoNextCompareSource, rewriteForwardCopyIntoNextCompareSource},
            {"fold_copy_op_copy_back", PeepholeRuleTarget::LoadRegReg, matchFoldCopyOpCopyBack, rewriteFoldCopyOpCopyBack},
            {"fold_copy_unary_copy_back", PeepholeRuleTarget::LoadRegReg, matchFoldCopyUnaryCopyBack, rewriteFoldCopyUnaryCopyBack},
            {"fold_copy_back_with_previous_op", PeepholeRuleTarget::LoadRegReg, matchFoldCopyBackWithPreviousOp, rewriteFoldCopyBackWithPreviousOp},
            {"coalesce_copy_instruction", PeepholeRuleTarget::LoadRegReg, matchCoalesceCopyInstruction, rewriteCoalesceCopyInstruction},
            {"remove_overwritten_copy", PeepholeRuleTarget::LoadRegReg, matchRemoveOverwrittenCopy, rewriteRemoveOverwrittenCopy},
            {"canonicalize_cmp_reg_imm_zero", PeepholeRuleTarget::AnyInstruction, matchCanonicalizeCmpRegImmZero, rewriteCanonicalizeCmpRegImmZero},
            {"fold_setcond_zeroext_copy", PeepholeRuleTarget::AnyInstruction, matchFoldSetCondZeroExtCopy, rewriteFoldSetCondZeroExtCopy},
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
