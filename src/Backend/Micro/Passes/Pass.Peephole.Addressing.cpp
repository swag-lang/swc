#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool foldZeroIndexAmcFromImmediate(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            if (ops[2].valueU64 != 0)
                return false;
            if (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64)
                return false;

            const MicroReg indexReg = ops[0].reg;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                MicroInstr&        scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *SWC_CHECK_NOT_NULL(ref.reg) != indexReg)
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

                if (!isTempDeadForAddressFold(context, std::next(scanIt), endIt, indexReg))
                    return false;

                const MicroInstrOpcode                 originalOp  = scanInst.op;
                const std::array<MicroInstrOperand, 8> originalOps = {scanOps[0], scanOps[1], scanOps[2], scanOps[3], scanOps[4], scanOps[5], scanOps[6], scanOps[7]};

                if (scanInst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                {
                    if (scanOps[2].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadAddrRegMem;
                    scanOps[2].opBits   = scanOps[3].opBits;
                    scanOps[3].valueU64 = scanOps[6].valueU64;
                }
                else if (scanInst.op == MicroInstrOpcode::LoadAmcRegMem)
                {
                    if (scanOps[2].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadRegMem;
                    scanOps[2].opBits   = scanOps[3].opBits;
                    scanOps[3].valueU64 = scanOps[6].valueU64;
                }
                else if (scanInst.op == MicroInstrOpcode::LoadAmcMemReg)
                {
                    if (scanOps[1].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadMemReg;
                    scanOps[1].reg      = scanOps[2].reg;
                    scanOps[2].opBits   = scanOps[4].opBits;
                    scanOps[3].valueU64 = scanOps[6].valueU64;
                }
                else if (scanInst.op == MicroInstrOpcode::LoadAmcMemImm)
                {
                    if (scanOps[1].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadMemImm;
                    scanOps[1].opBits   = scanOps[4].opBits;
                    scanOps[2].valueU64 = scanOps[6].valueU64;
                    scanOps[3].valueU64 = scanOps[7].valueU64;
                }
                else
                {
                    return false;
                }

                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanInst.op = originalOp;
                    for (uint32_t i = 0; i < 8; ++i)
                        scanOps[i] = originalOps[i];
                    return false;
                }

                SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool foldCopyAddIntoLoadAddress(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            if (nextOps[0].reg != ops[0].reg)
                return false;
            if (ops[2].opBits != MicroOpBits::B64 || nextOps[1].opBits != MicroOpBits::B64)
                return false;
            if (nextOps[2].microOp != MicroOp::Add)
                return false;
            if (!ops[0].reg.isSameClass(ops[1].reg))
                return false;
            if (!areFlagsDeadAfterInstruction(context, nextIt, endIt))
                return false;

            const MicroReg    tmpReg       = ops[0].reg;
            const MicroReg    baseReg      = ops[1].reg;
            const uint64_t    offset       = nextOps[3].valueU64;
            const MicroReg    originalDst  = nextOps[0].reg;
            const MicroOpBits originalBits = nextOps[1].opBits;
            const MicroOp     originalOp   = nextOps[2].microOp;
            const uint64_t    originalImm  = nextOps[3].valueU64;

            nextInst.op         = MicroInstrOpcode::LoadAddrRegMem;
            nextOps[0].reg      = tmpReg;
            nextOps[1].reg      = baseReg;
            nextOps[2].opBits   = MicroOpBits::B64;
            nextOps[3].valueU64 = offset;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextInst.op         = MicroInstrOpcode::OpBinaryRegImm;
                nextOps[0].reg      = originalDst;
                nextOps[1].opBits   = originalBits;
                nextOps[2].microOp  = originalOp;
                nextOps[3].valueU64 = originalImm;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldLoadAddrIntoNextMemOffset(const MicroPassContext& context, const Cursor& cursor)
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

            uint8_t baseIndex   = 0;
            uint8_t offsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, nextInst))
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[baseIndex].reg != tmpReg)
                return false;
            if (!isTempDeadForAddressFold(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const uint64_t extraOffset  = ops[3].valueU64;
            const uint64_t oldMemOffset = nextOps[offsetIndex].valueU64;
            if (oldMemOffset > std::numeric_limits<uint64_t>::max() - extraOffset)
                return false;
            const uint64_t foldedMemOffset = oldMemOffset + extraOffset;

            const MicroReg originalBaseReg = nextOps[baseIndex].reg;
            const uint64_t originalOffset  = nextOps[offsetIndex].valueU64;
            nextOps[baseIndex].reg         = ops[1].reg;
            nextOps[offsetIndex].valueU64  = foldedMemOffset;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextOps[baseIndex].reg        = originalBaseReg;
                nextOps[offsetIndex].valueU64 = originalOffset;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldLoadAddrAmcIntoNextMemoryAccess(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const uint64_t mulValue = ops[5].valueU64;
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (!isTempDeadForAddressFold(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const MicroInstr&  nextInst = *nextIt;
            MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            MicroInstrOpcode newOpcode = MicroInstrOpcode::End;
            uint64_t         nextOffset{};
            if (nextInst.op == MicroInstrOpcode::LoadRegMem)
            {
                if (nextOps[1].reg != tmpReg)
                    return false;

                newOpcode   = MicroInstrOpcode::LoadAmcRegMem;
                nextOffset  = nextOps[3].valueU64;
            }
            else if (nextInst.op == MicroInstrOpcode::LoadMemReg)
            {
                if (nextOps[0].reg != tmpReg)
                    return false;

                newOpcode   = MicroInstrOpcode::LoadAmcMemReg;
                nextOffset  = nextOps[3].valueU64;
            }
            else if (nextInst.op == MicroInstrOpcode::LoadMemImm)
            {
                if (nextOps[0].reg != tmpReg)
                    return false;

                newOpcode   = MicroInstrOpcode::LoadAmcMemImm;
                nextOffset  = nextOps[2].valueU64;
            }
            else
            {
                return false;
            }

            if (ops[6].valueU64 > std::numeric_limits<uint64_t>::max() - nextOffset)
                return false;
            const uint64_t combinedAdd = ops[6].valueU64 + nextOffset;

            MicroInstr* rewriteInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(instRef);
            if (!rewriteInst)
                return false;

            MicroInstrOperand* rewriteOps = rewriteInst->ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!rewriteOps)
                return false;

            const MicroInstrOpcode                 originalOp  = rewriteInst->op;
            const std::array<MicroInstrOperand, 8> originalOps = {rewriteOps[0], rewriteOps[1], rewriteOps[2], rewriteOps[3], rewriteOps[4], rewriteOps[5], rewriteOps[6], rewriteOps[7]};

            rewriteInst->op        = newOpcode;
            rewriteOps[5].valueU64 = ops[5].valueU64;
            rewriteOps[6].valueU64 = combinedAdd;
            rewriteOps[7].valueU64 = 0;

            if (newOpcode == MicroInstrOpcode::LoadAmcRegMem)
            {
                rewriteOps[0].reg    = nextOps[0].reg;
                rewriteOps[1].reg    = ops[1].reg;
                rewriteOps[2].reg    = ops[2].reg;
                rewriteOps[3].opBits = nextOps[2].opBits;
                rewriteOps[4].opBits = ops[4].opBits;
            }
            else if (newOpcode == MicroInstrOpcode::LoadAmcMemReg)
            {
                rewriteOps[0].reg    = ops[1].reg;
                rewriteOps[1].reg    = ops[2].reg;
                rewriteOps[2].reg    = nextOps[1].reg;
                rewriteOps[3].opBits = ops[4].opBits;
                rewriteOps[4].opBits = nextOps[2].opBits;
            }
            else
            {
                rewriteOps[0].reg      = ops[1].reg;
                rewriteOps[1].reg      = ops[2].reg;
                rewriteOps[3].opBits   = ops[4].opBits;
                rewriteOps[4].opBits   = nextOps[1].opBits;
                rewriteOps[7].valueU64 = nextOps[3].valueU64;
            }

            if (MicroOptimization::violatesEncoderConformance(context, *rewriteInst, rewriteOps))
            {
                rewriteInst->op = originalOp;
                for (uint32_t i = 0; i < 8; ++i)
                    rewriteOps[i] = originalOps[i];
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(nextIt.current);
            return true;
        }

    }

    void appendAddressingRules(RuleList& outRules)
    {
        outRules.push_back({RuleTarget::LoadRegImm, foldZeroIndexAmcFromImmediate});

        // Rule: fold_copy_add_into_load_address
        // Purpose: fold copy + add-immediate into one address load.
        // Example: mov r11, rdx; add r11, 8 -> lea r11, [rdx + 8]
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyAddIntoLoadAddress});

        // Rule: fold_loadaddr_into_next_mem_offset
        // Purpose: consume temporary address register in next memory instruction.
        // Example: lea r11, [rdx + 8]; mov [r11], rax -> mov [rdx + 8], rax
        outRules.push_back({RuleTarget::LoadAddrRegMem, foldLoadAddrIntoNextMemOffset});

        // Rule: fold_loadaddramc_into_next_memory_access
        // Purpose: consume temporary AMC address register by folding next memory access into AMC form.
        // Example: lea r11, [r8 + r9 * 16]; mov rdx, [r11] -> mov rdx, [r8 + r9 * 16]
        outRules.push_back({RuleTarget::LoadAddrAmcRegMem, foldLoadAddrAmcIntoNextMemoryAccess});
    }
}

SWC_END_NAMESPACE();
