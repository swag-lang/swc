#include "pch.h"
#include "Backend/Micro/Passes/Pass.PrologEpilogSanitize.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isFramePointerSetupInstruction(const CallConv& conv, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg stackPointer)
    {
        if (!ops || !conv.framePointer.isValid())
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                if (inst.numOperands < 3)
                    return false;
                return ops[0].reg == conv.framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            case MicroInstrOpcode::LoadAddrRegMem:
                if (inst.numOperands < 4)
                    return false;
                return ops[0].reg == conv.framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            default:
                return false;
        }
    }

    bool isStackAdjustWithOp(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroOp expectedOp, uint64_t& outImmediate)
    {
        outImmediate = 0;
        if (!ops || inst.op != MicroInstrOpcode::OpBinaryRegImm || inst.numOperands < 4)
            return false;
        if (ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64)
            return false;
        if (ops[2].microOp != expectedOp)
            return false;

        const ApInt immediate = ops[3].immediateValue(64);
        if (!immediate.fit64())
            return false;

        outImmediate = immediate.as64();
        return true;
    }

    bool isPrologueInstruction(const CallConv& conv, const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::Push:
                return inst.numOperands >= 1;

            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
                return isFramePointerSetupInstruction(conv, inst, ops, stackPointer);

            case MicroInstrOpcode::LoadMemReg:
                if (inst.numOperands < 4)
                    return false;
                return ops[0].reg == stackPointer;

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                uint64_t immediate = 0;
                return isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Subtract, immediate);
            }

            default:
                return false;
        }
    }

    bool isEpilogueInstruction(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::Pop:
                return inst.numOperands >= 1;

            case MicroInstrOpcode::LoadRegMem:
                if (inst.numOperands < 4)
                    return false;
                return ops[1].reg == stackPointer;

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                uint64_t immediate = 0;
                return isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Add, immediate);
            }

            default:
                return false;
        }
    }

    bool tryMergeAdjacentStackAdjust(MicroPassContext& context, MicroInstrRef firstRef, MicroInstrRef secondRef, MicroReg stackPointer, MicroOp expectedOp)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (firstRef.isInvalid() || secondRef.isInvalid())
            return false;
        if (context.instructions->findPreviousInstructionRef(secondRef) != firstRef)
            return false;

        MicroInstr*       firstInst  = context.instructions->ptr(firstRef);
        const MicroInstr* secondInst = context.instructions->ptr(secondRef);
        if (!firstInst || !secondInst)
            return false;

        MicroInstrOperand*       firstOps  = firstInst->ops(*context.operands);
        const MicroInstrOperand* secondOps = secondInst->ops(*context.operands);
        if (!firstOps || !secondOps)
            return false;

        uint64_t firstImmediate  = 0;
        uint64_t secondImmediate = 0;
        if (!isStackAdjustWithOp(*firstInst, firstOps, stackPointer, expectedOp, firstImmediate))
            return false;
        if (!isStackAdjustWithOp(*secondInst, secondOps, stackPointer, expectedOp, secondImmediate))
            return false;
        if (firstImmediate > std::numeric_limits<uint64_t>::max() - secondImmediate)
            return false;

        const ApInt    originalImmediate = firstOps[3].immediateValue(64);
        const uint64_t mergedImmediate   = firstImmediate + secondImmediate;
        firstOps[3].setImmediateValue(ApInt(mergedImmediate, 64));

        if (MicroPassHelpers::violatesEncoderConformance(context, *firstInst, firstOps))
        {
            firstOps[3].setImmediateValue(originalImmediate);
            return false;
        }

        context.instructions->erase(secondRef);
        return true;
    }

    bool sanitizePrologueFramePointerSetups(MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        std::vector<MicroInstrRef> framePointerSetupRefs;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            const MicroInstrOperand* ops = it->ops(*context.operands);
            if (!isPrologueInstruction(conv, *it, ops, conv.stackPointer))
                break;

            if (isFramePointerSetupInstruction(conv, *it, ops, conv.stackPointer))
                framePointerSetupRefs.push_back(it.current);
        }

        if (framePointerSetupRefs.size() < 2)
            return false;

        // Keep the last frame-pointer setup and remove older ones from the entry prologue.
        for (size_t i = framePointerSetupRefs.size() - 1; i > 0; --i)
            context.instructions->erase(framePointerSetupRefs[i - 1]);

        return true;
    }

    bool sanitizePrologueStackAdjustments(MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        bool changedAny = false;
        bool retry      = true;
        while (retry)
        {
            retry     = false;
            auto view = context.instructions->view();
            for (auto it = view.begin(); it != view.end(); ++it)
            {
                const MicroInstrOperand* ops = it->ops(*context.operands);
                if (!isPrologueInstruction(conv, *it, ops, conv.stackPointer))
                    return changedAny;

                auto nextIt = it;
                ++nextIt;
                if (nextIt == view.end())
                    return changedAny;

                const MicroInstrOperand* nextOps = nextIt->ops(*context.operands);
                if (!isPrologueInstruction(conv, *nextIt, nextOps, conv.stackPointer))
                    return changedAny;

                if (tryMergeAdjacentStackAdjust(context, it.current, nextIt.current, conv.stackPointer, MicroOp::Subtract))
                {
                    changedAny = true;
                    retry      = true;
                    break;
                }
            }
        }

        return changedAny;
    }

    bool sanitizeEpilogueStackAdjustments(MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        std::vector<MicroInstrRef> retRefs;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            if (it->op == MicroInstrOpcode::Ret)
                retRefs.push_back(it.current);
        }

        bool changedAny = false;
        for (const MicroInstrRef retRef : retRefs)
        {
            bool retry = true;
            while (retry)
            {
                retry = false;
                if (!context.instructions->ptr(retRef))
                    break;

                std::vector<MicroInstrRef> epilogueRefs;
                for (MicroInstrRef ref = context.instructions->findPreviousInstructionRef(retRef); ref.isValid(); ref = context.instructions->findPreviousInstructionRef(ref))
                {
                    const MicroInstr* inst = context.instructions->ptr(ref);
                    if (!inst)
                        break;

                    const MicroInstrOperand* ops = inst->ops(*context.operands);
                    if (!isEpilogueInstruction(*inst, ops, conv.stackPointer))
                        break;

                    epilogueRefs.push_back(ref);
                }

                if (epilogueRefs.size() < 2)
                    break;

                std::reverse(epilogueRefs.begin(), epilogueRefs.end());
                for (size_t i = 0; i + 1 < epilogueRefs.size(); ++i)
                {
                    if (tryMergeAdjacentStackAdjust(context, epilogueRefs[i], epilogueRefs[i + 1], conv.stackPointer, MicroOp::Add))
                    {
                        changedAny = true;
                        retry      = true;
                        break;
                    }
                }
            }
        }

        return changedAny;
    }
}

Result MicroPrologEpilogSanitizePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    const CallConv& conv                      = CallConv::get(context.callConvKind);
    const bool      changedFramePointerProlog = sanitizePrologueFramePointerSetups(context, conv);
    const bool      changedStackProlog        = sanitizePrologueStackAdjustments(context, conv);
    const bool      changedStackEpilogue      = sanitizeEpilogueStackAdjustments(context, conv);
    const bool      changed                   = changedFramePointerProlog || changedStackProlog || changedStackEpilogue;
    context.passChanged                       = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
