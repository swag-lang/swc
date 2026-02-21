#include "pch.h"
#include "Backend/Micro/Passes/MicroPeepholePass.Private.h"
#include "Backend/Micro/MicroOptimization.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool tryFoldLoadImmIntoNextMemStore(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            if (ops[1].opBits != MicroOpBits::B64)
                return false;

            const MicroReg tmpReg = ops[0].reg;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                MicroInstr&            scanInst = *scanIt;
                MicroInstrOperand*     scanOps  = scanInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *SWC_CHECK_NOT_NULL(ref.reg) != tmpReg)
                        continue;

                    hasUse |= ref.use;
                    hasDef |= ref.def;
                }

                if (hasDef)
                    return false;

                if (!hasUse)
                {
                    if (useDef.isCall || MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
                        return false;
                    continue;
                }

                if (scanInst.op != MicroInstrOpcode::LoadMemReg || !scanOps || scanOps[1].reg != tmpReg)
                    return false;
                if (!isTempDeadForAddressFold(context, std::next(scanIt), endIt, tmpReg))
                    return false;

                const MicroInstrOpcode                 originalOp  = scanInst.op;
                const std::array<MicroInstrOperand, 4> originalOps = {scanOps[0], scanOps[1], scanOps[2], scanOps[3]};

                const MicroOpBits storeBits = originalOps[2].opBits;
                uint64_t          value     = ops[2].valueU64;
                if (storeBits != MicroOpBits::B64)
                    value &= getOpBitsMask(storeBits);

                scanInst.op         = MicroInstrOpcode::LoadMemImm;
                scanOps[0]          = originalOps[0];
                scanOps[1].opBits   = storeBits;
                scanOps[2].valueU64 = originalOps[3].valueU64;
                scanOps[3].valueU64 = value;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanInst.op = originalOp;
                    for (uint32_t i = 0; i < 4; ++i)
                        scanOps[i] = originalOps[i];
                    return false;
                }

                SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool tryFoldLoadImmIntoNextCopy(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::LoadRegReg)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[1].reg != tmpReg)
                return false;
            if (ops[1].opBits != nextOps[2].opBits)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const MicroInstrOpcode                 originalOp  = nextInst.op;
            const std::array<MicroInstrOperand, 3> originalOps = {nextOps[0], nextOps[1], nextOps[2]};

            uint64_t         immValue = ops[2].valueU64;
            const MicroOpBits opBits   = originalOps[2].opBits;
            if (opBits != MicroOpBits::B64)
                immValue &= getOpBitsMask(opBits);

            nextInst.op         = MicroInstrOpcode::LoadRegImm;
            nextOps[0]          = originalOps[0];
            nextOps[1].opBits   = opBits;
            nextOps[2].valueU64 = immValue;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextInst.op = originalOp;
                for (uint32_t i = 0; i < 3; ++i)
                    nextOps[i] = originalOps[i];
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool tryFoldLoadImmIntoNextBinary(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::OpBinaryRegReg)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[1].reg != tmpReg || nextOps[0].reg == tmpReg)
                return false;
            if (ops[1].opBits != nextOps[2].opBits)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const MicroInstrOpcode                 originalOp  = nextInst.op;
            const std::array<MicroInstrOperand, 4> originalOps = {nextOps[0], nextOps[1], nextOps[2], nextOps[3]};

            uint64_t         immValue = ops[2].valueU64;
            const MicroOpBits opBits   = originalOps[2].opBits;
            if (opBits != MicroOpBits::B64)
                immValue &= getOpBitsMask(opBits);

            nextInst.op         = MicroInstrOpcode::OpBinaryRegImm;
            nextOps[0]          = originalOps[0];
            nextOps[1].opBits   = opBits;
            nextOps[2].microOp  = originalOps[3].microOp;
            nextOps[3].valueU64 = immValue;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextInst.op = originalOp;
                for (uint32_t i = 0; i < 4; ++i)
                    nextOps[i] = originalOps[i];
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool tryFoldLoadImmIntoNextCompare(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::CmpRegReg)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[1].reg != tmpReg || nextOps[0].reg == tmpReg)
                return false;
            if (ops[1].opBits != nextOps[2].opBits)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const MicroInstrOpcode                 originalOp  = nextInst.op;
            const std::array<MicroInstrOperand, 3> originalOps = {nextOps[0], nextOps[1], nextOps[2]};

            uint64_t         immValue = ops[2].valueU64;
            const MicroOpBits opBits   = originalOps[2].opBits;
            if (opBits != MicroOpBits::B64)
                immValue &= getOpBitsMask(opBits);

            nextInst.op         = MicroInstrOpcode::CmpRegImm;
            nextOps[0]          = originalOps[0];
            nextOps[1].opBits   = opBits;
            nextOps[2].valueU64 = immValue;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextInst.op = originalOp;
                for (uint32_t i = 0; i < 3; ++i)
                    nextOps[i] = originalOps[i];
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool tryFoldAdjacentMemImm32Stores(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::LoadMemImm)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            if (ops[1].opBits != MicroOpBits::B32 || nextOps[1].opBits != MicroOpBits::B32)
                return false;
            if (ops[0].reg != nextOps[0].reg)
                return false;

            const uint64_t firstOffset = ops[2].valueU64;
            const uint64_t nextOffset  = nextOps[2].valueU64;
            if (firstOffset > std::numeric_limits<uint64_t>::max() - 4)
                return false;
            if (firstOffset + 4 != nextOffset)
                return false;

            MicroInstr* firstInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(instRef);
            if (!firstInst)
                return false;

            MicroInstrOperand* firstOps = firstInst->ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!firstOps)
                return false;

            const MicroInstrOpcode                 originalFirstOp  = firstInst->op;
            const std::array<MicroInstrOperand, 4> originalFirstOps = {firstOps[0], firstOps[1], firstOps[2], firstOps[3]};

            const uint64_t loValue = originalFirstOps[3].valueU64 & getOpBitsMask(MicroOpBits::B32);
            const uint64_t hiValue = nextOps[3].valueU64 & getOpBitsMask(MicroOpBits::B32);
            const uint64_t merged  = loValue | (hiValue << 32);

            firstInst->op        = MicroInstrOpcode::LoadMemImm;
            firstOps[1].opBits   = MicroOpBits::B64;
            firstOps[3].valueU64 = merged;
            if (MicroOptimization::violatesEncoderConformance(context, *firstInst, firstOps))
            {
                firstInst->op = originalFirstOp;
                for (uint32_t i = 0; i < 4; ++i)
                    firstOps[i] = originalFirstOps[i];
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(nextIt.current);
            return true;
        }

        bool isStackPointerReg(const MicroPassContext& context, MicroReg reg)
        {
            if (!reg.isValid() || reg.isNoBase())
                return false;

            if (context.encoder)
            {
                const MicroReg stackPointerReg = context.encoder->stackPointerReg();
                if (stackPointerReg.isValid())
                    return reg == stackPointerReg;
            }

            return reg.isInt() && reg.index() == 4;
        }

        bool isMergeableRspAdjustInstruction(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops, MicroOp expectedOp)
        {
            if (!ops)
                return false;

            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;
            if (ops[1].opBits != MicroOpBits::B64)
                return false;
            if (ops[2].microOp != expectedOp)
                return false;

            return isStackPointerReg(context, ops[0].reg);
        }

        bool isRspMergeNeutralInstruction(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (!ops)
                return false;

            if (inst.op != MicroInstrOpcode::LoadRegReg)
                return false;

            return !isStackPointerReg(context, ops[0].reg) && !isStackPointerReg(context, ops[1].reg);
        }

        bool tryMergeRspAdjustmentsAtStart(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            if (ops[1].opBits != MicroOpBits::B64)
                return false;

            const MicroOp firstOp = ops[2].microOp;
            if (firstOp != MicroOp::Add && firstOp != MicroOp::Subtract)
                return false;

            if (!isStackPointerReg(context, ops[0].reg))
                return false;

            const MicroInstr&        firstNextInst = *nextIt;
            const MicroInstrOperand* firstNextOps  = firstNextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));

            MicroStorage::Iterator   secondAdjustIt;
            const MicroInstrOperand* secondAdjustOps = nullptr;
            if (isMergeableRspAdjustInstruction(context, firstNextInst, firstNextOps, firstOp))
            {
                secondAdjustIt  = nextIt;
                secondAdjustOps = firstNextOps;
            }
            else
            {
                if (!isRspMergeNeutralInstruction(context, firstNextInst, firstNextOps))
                    return false;

                secondAdjustIt = std::next(nextIt);
                if (secondAdjustIt == endIt)
                    return false;

                const MicroInstr&        secondInst = *secondAdjustIt;
                const MicroInstrOperand* secondOps  = secondInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                if (!isMergeableRspAdjustInstruction(context, secondInst, secondOps, firstOp))
                    return false;

                secondAdjustOps = secondOps;
            }

            if (!secondAdjustOps)
                return false;

            if (!areFlagsDeadAfterInstruction(context, secondAdjustIt, endIt))
                return false;

            const uint64_t firstImm  = ops[3].valueU64;
            const uint64_t secondImm = secondAdjustOps[3].valueU64;
            if (firstImm > std::numeric_limits<uint64_t>::max() - secondImm)
                return false;

            MicroInstr* firstInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(instRef);
            if (!firstInst)
                return false;

            MicroInstrOperand* firstOps = firstInst->ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!firstOps)
                return false;

            const uint64_t originalImm = firstOps[3].valueU64;
            firstOps[3].valueU64        = firstImm + secondImm;
            if (MicroOptimization::violatesEncoderConformance(context, *firstInst, firstOps))
            {
                firstOps[3].valueU64 = originalImm;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(secondAdjustIt.current);
            return true;
        }

        bool matchMergeRspAdjustmentsAtStart(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            if (cursor.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;
            if (cursor.ops[1].opBits != MicroOpBits::B64)
                return false;
            if (cursor.ops[2].microOp != MicroOp::Add && cursor.ops[2].microOp != MicroOp::Subtract)
                return false;

            return isStackPointerReg(context, cursor.ops[0].reg);
        }

        bool rewriteMergeRspAdjustmentsAtStart(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryMergeRspAdjustmentsAtStart(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldLoadImmIntoNextMemStore(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.ops != nullptr && cursor.nextIt != cursor.endIt;
        }

        bool rewriteFoldLoadImmIntoNextMemStore(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldLoadImmIntoNextMemStore(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldLoadImmIntoNextCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.ops != nullptr && cursor.nextIt != cursor.endIt;
        }

        bool rewriteFoldLoadImmIntoNextCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldLoadImmIntoNextCopy(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldLoadImmIntoNextBinary(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.ops != nullptr && cursor.nextIt != cursor.endIt;
        }

        bool rewriteFoldLoadImmIntoNextBinary(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldLoadImmIntoNextBinary(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldLoadImmIntoNextCompare(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.ops != nullptr && cursor.nextIt != cursor.endIt;
        }

        bool rewriteFoldLoadImmIntoNextCompare(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldLoadImmIntoNextCompare(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldAdjacentMemImm32Stores(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.ops != nullptr && cursor.nextIt != cursor.endIt;
        }

        bool rewriteFoldAdjacentMemImm32Stores(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldAdjacentMemImm32Stores(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }
    }

    void appendImmediateRules(RuleList& outRules)
    {
        outRules.push_back({"merge_rsp_adjustments_at_start", RuleTarget::OpBinaryRegImm, matchMergeRspAdjustmentsAtStart, rewriteMergeRspAdjustmentsAtStart});
        outRules.push_back({"fold_loadimm_into_next_copy", RuleTarget::LoadRegImm, matchFoldLoadImmIntoNextCopy, rewriteFoldLoadImmIntoNextCopy});
        outRules.push_back({"fold_loadimm_into_next_binary", RuleTarget::LoadRegImm, matchFoldLoadImmIntoNextBinary, rewriteFoldLoadImmIntoNextBinary});
        outRules.push_back({"fold_loadimm_into_next_compare", RuleTarget::LoadRegImm, matchFoldLoadImmIntoNextCompare, rewriteFoldLoadImmIntoNextCompare});
        outRules.push_back({"fold_loadimm_into_next_mem_store", RuleTarget::LoadRegImm, matchFoldLoadImmIntoNextMemStore, rewriteFoldLoadImmIntoNextMemStore});
        outRules.push_back({"fold_adjacent_memimm32_stores", RuleTarget::LoadMemImm, matchFoldAdjacentMemImm32Stores, rewriteFoldAdjacentMemImm32Stores});
    }
}

SWC_END_NAMESPACE();
