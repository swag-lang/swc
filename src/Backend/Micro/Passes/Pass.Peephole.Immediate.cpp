#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool foldLoadImmIntoNextMemStore(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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
                    if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
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

        bool foldLoadImmIntoNextCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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

            uint64_t          immValue = ops[2].valueU64;
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

        bool foldLoadImmIntoNextBinary(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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

            uint64_t          immValue = ops[2].valueU64;
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

        bool foldLoadImmIntoNextCompare(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
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

            uint64_t          immValue = ops[2].valueU64;
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

        bool foldAdjacentMemImm32Stores(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::LoadMemImm)
                return false;

            const MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
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

        bool isMergeableRegImmArithmeticInstruction(const MicroInstr&        inst,
                                                    const MicroInstrOperand* ops,
                                                    MicroReg                 expectedReg,
                                                    MicroOpBits              expectedBits,
                                                    MicroOp                  expectedOp)
        {
            if (!ops)
                return false;

            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;
            if (ops[0].reg != expectedReg)
                return false;
            if (ops[1].opBits != expectedBits)
                return false;
            if (ops[2].microOp != expectedOp)
                return false;
            return true;
        }

        bool isRegImmMergeNeutralInstruction(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg mergedReg)
        {
            if (!ops)
                return false;

            const MicroInstrUseDef useDef = inst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::JumpCond:
                case MicroInstrOpcode::JumpCondImm:
                case MicroInstrOpcode::SetCondReg:
                case MicroInstrOpcode::LoadCondRegReg:
                    return false;
                default:
                    break;
            }

            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg)
                    continue;

                if (*SWC_CHECK_NOT_NULL(ref.reg) == mergedReg)
                    return false;
            }

            return true;
        }

        bool mergeRegImmArithmeticWithNext(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg    mergedReg = ops[0].reg;
            const MicroOpBits opBits    = ops[1].opBits;
            const MicroOp     microOp   = ops[2].microOp;
            if (!mergedReg.isValid() || mergedReg.isNoBase())
                return false;
            if (microOp != MicroOp::Add && microOp != MicroOp::Subtract)
                return false;

            const MicroInstr&        firstNextInst = *nextIt;
            const MicroInstrOperand* firstNextOps  = firstNextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));

            MicroStorage::Iterator   secondAdjustIt;
            const MicroInstrOperand* secondAdjustOps = nullptr;
            if (isMergeableRegImmArithmeticInstruction(firstNextInst, firstNextOps, mergedReg, opBits, microOp))
            {
                secondAdjustIt  = nextIt;
                secondAdjustOps = firstNextOps;
            }
            else
            {
                if (!isRegImmMergeNeutralInstruction(context, firstNextInst, firstNextOps, mergedReg))
                    return false;

                secondAdjustIt = std::next(nextIt);
                if (secondAdjustIt == endIt)
                    return false;

                const MicroInstr&        secondInst = *secondAdjustIt;
                const MicroInstrOperand* secondOps  = secondInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                if (!isMergeableRegImmArithmeticInstruction(secondInst, secondOps, mergedReg, opBits, microOp))
                    return false;

                secondAdjustOps = secondOps;
            }

            if (!secondAdjustOps)
                return false;

            if (!areFlagsDeadAfterInstruction(context, secondAdjustIt, endIt))
                return false;

            MicroInstr* firstInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(instRef);
            if (!firstInst)
                return false;

            MicroInstrOperand* firstOps = firstInst->ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!firstOps)
                return false;

            const uint64_t originalImm = firstOps[3].valueU64;
            const uint64_t firstImm    = originalImm;
            const uint64_t secondImm   = secondAdjustOps[3].valueU64;
            uint64_t       combinedImm = firstImm + secondImm;
            if (opBits != MicroOpBits::B64)
                combinedImm &= getOpBitsMask(opBits);
            firstOps[3].valueU64 = combinedImm;
            if (MicroOptimization::violatesEncoderConformance(context, *firstInst, firstOps))
            {
                firstOps[3].valueU64 = originalImm;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(secondAdjustIt.current);
            return true;
        }

    }

    void appendImmediateRules(RuleList& outRules)
    {
        // Rule: merge_regimm_arithmetic_with_next
        // Purpose: merge two same-register immediate add/sub operations into one, anywhere in the block.
        // Example: add rax, 4; mov r9, rcx; add rax, 8 -> add rax, 12; mov r9, rcx
        outRules.push_back({RuleTarget::OpBinaryRegImm, mergeRegImmArithmeticWithNext});

        // Rule: fold_loadimm_into_next_copy
        // Purpose: fold an immediate load through a copy and remove temporary register.
        // Example: mov r11, 42; mov rax, r11 -> mov rax, 42
        outRules.push_back({RuleTarget::LoadRegImm, foldLoadImmIntoNextCopy});

        // Rule: fold_loadimm_into_next_binary
        // Purpose: fold reg-reg binary operation with temp immediate into reg-immediate form.
        // Example: mov r11, 42; add rax, r11 -> add rax, 42
        outRules.push_back({RuleTarget::LoadRegImm, foldLoadImmIntoNextBinary});

        // Rule: fold_loadimm_into_next_compare
        // Purpose: fold reg-reg compare with temp immediate into reg-immediate compare.
        // Example: mov r11, 7; cmp rax, r11 -> cmp rax, 7
        outRules.push_back({RuleTarget::LoadRegImm, foldLoadImmIntoNextCompare});

        // Rule: fold_loadimm_into_next_mem_store
        // Purpose: store immediate directly to memory instead of via temporary register.
        // Example: mov r11, 1; mov [rdx], r11 -> mov [rdx], 1
        outRules.push_back({RuleTarget::LoadRegImm, foldLoadImmIntoNextMemStore});

        // Rule: fold_adjacent_memimm32_stores
        // Purpose: merge two contiguous 32-bit immediate stores into one 64-bit store.
        // Example: mov [rdx], 1; mov [rdx + 4], 2 -> mov [rdx], 0x0000000200000001
        outRules.push_back({RuleTarget::LoadMemImm, foldAdjacentMemImm32Stores});
    }
}

SWC_END_NAMESPACE();
