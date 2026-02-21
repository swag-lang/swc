#include "pch.h"
#include "Backend/Micro/MicroInstructionInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/MicroPeepholePass.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool tryFoldCopyAddIntoLoadAddress(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
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
            if (!MicroInstructionInfo::isSameRegisterClass(ops[0].reg, ops[1].reg))
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

        bool tryFoldLoadAddrIntoNextMemOffset(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&  nextInst = *nextIt;
            MicroInstrOperand* nextOps  = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            uint8_t baseIndex   = 0;
            uint8_t offsetIndex = 0;
            if (!getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, nextInst))
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

        bool matchFoldCopyAddIntoLoadAddress(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroInstr& nextInst = *cursor.nextIt;
            if (nextInst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* nextOps = nextInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            return nextOps[2].microOp == MicroOp::Add;
        }

        bool rewriteFoldCopyAddIntoLoadAddress(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldCopyAddIntoLoadAddress(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }

        bool matchFoldLoadAddrIntoNextMemOffset(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            uint8_t           baseIndex   = 0;
            uint8_t           offsetIndex = 0;
            const MicroInstr& nextInst    = *cursor.nextIt;
            SWC_UNUSED(context);
            return getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, nextInst);
        }

        bool rewriteFoldLoadAddrIntoNextMemOffset(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldLoadAddrIntoNextMemOffset(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }
    }

    void appendAddressingRules(RuleList& outRules)
    {
        // Rule: fold_copy_add_into_load_address
        // Purpose: fold copy + add-immediate into one address load.
        // Example: mov r11, rdx; add r11, 8 -> lea r11, [rdx + 8]
        outRules.push_back({"fold_copy_add_into_load_address", RuleTarget::LoadRegReg, matchFoldCopyAddIntoLoadAddress, rewriteFoldCopyAddIntoLoadAddress});

        // Rule: fold_loadaddr_into_next_mem_offset
        // Purpose: consume temporary address register in next memory instruction.
        // Example: lea r11, [rdx + 8]; mov [r11], rax -> mov [rdx + 8], rax
        outRules.push_back({"fold_loadaddr_into_next_mem_offset", RuleTarget::LoadAddrRegMem, matchFoldLoadAddrIntoNextMemOffset, rewriteFoldLoadAddrIntoNextMemOffset});
    }
}

SWC_END_NAMESPACE();

