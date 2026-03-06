#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.StackAdjustNormalize.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runStackAdjustNormalizePass(MicroBuilder& builder)
    {
        MicroStackAdjustNormalizePass pass;
        MicroPassManager              passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    bool isStackAdjust(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroOp expectedOp, uint64_t expectedImmediate)
    {
        if (!ops)
            return false;
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm || inst.numOperands < 4)
            return false;
        if (ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64)
            return false;
        if (ops[2].microOp != expectedOp)
            return false;
        if (ops[3].valueU64 != expectedImmediate)
            return false;
        return true;
    }

    bool findStoreOffsetForSourceReg(const MicroBuilder& builder, MicroReg srcReg, uint64_t& outOffset)
    {
        outOffset = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadMemReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (!ops || inst.numOperands < 4)
                continue;
            if (ops[1].reg != srcReg)
                continue;

            outOffset = ops[3].valueU64;
            return true;
        }

        return false;
    }
}

SWC_TEST_BEGIN(MicroStackAdjustNormalize_RemovesBodyAdjustsAndRebasesOffsets)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r11 = MicroReg::intReg(11);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(rsp, ApInt(40, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0, r10, MicroOpBits::B64);
    builder.emitCallReg(rax, CallConvKind::Host);
    builder.emitOpBinaryRegImm(rsp, ApInt(40, 64), MicroOp::Add, MicroOpBits::B64);

    builder.emitOpBinaryRegImm(rsp, ApInt(56, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 32, r11, MicroOpBits::B64);
    builder.emitCallReg(rax, CallConvKind::Host);
    builder.emitOpBinaryRegImm(rsp, ApInt(56, 64), MicroOp::Add, MicroOpBits::B64);

    builder.emitRet();

    SWC_RESULT_VERIFY(runStackAdjustNormalizePass(builder));

    const MicroOperandStorage& operands = builder.operands();
    if (builder.instructions().count() != 7)
        return Result::Error;

    uint32_t stackAdjustCount = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(operands);
        if (isStackAdjust(inst, ops, rsp, MicroOp::Subtract, 56) || isStackAdjust(inst, ops, rsp, MicroOp::Add, 56))
            ++stackAdjustCount;
    }

    if (stackAdjustCount != 2)
        return Result::Error;

    const auto beginIt = builder.instructions().view().begin();
    if (beginIt == builder.instructions().view().end())
        return Result::Error;

    if (!isStackAdjust(*beginIt, beginIt->ops(operands), rsp, MicroOp::Subtract, 56))
        return Result::Error;

    MicroInstrRef retRef = MicroInstrRef::invalid();
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        if (it->op == MicroInstrOpcode::Ret)
        {
            retRef = it.current;
            break;
        }
    }

    if (retRef.isInvalid())
        return Result::Error;

    const MicroInstrRef beforeRetRef = builder.instructions().findPreviousInstructionRef(retRef);
    const MicroInstr*   beforeRet    = builder.instructions().ptr(beforeRetRef);
    if (!beforeRet)
        return Result::Error;

    if (!isStackAdjust(*beforeRet, beforeRet->ops(operands), rsp, MicroOp::Add, 56))
        return Result::Error;

    uint64_t firstStoreOffset  = 0;
    uint64_t secondStoreOffset = 0;
    if (!findStoreOffsetForSourceReg(builder, r10, firstStoreOffset))
        return Result::Error;
    if (!findStoreOffsetForSourceReg(builder, r11, secondStoreOffset))
        return Result::Error;

    if (firstStoreOffset != 16)
        return Result::Error;
    if (secondStoreOffset != 32)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroStackAdjustNormalize_HandlesBranchingDepths)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r11 = MicroReg::intReg(11);
    MicroBuilder       builder(ctx);

    const MicroLabelRef elseLabel = builder.createLabel();
    const MicroLabelRef doneLabel = builder.createLabel();

    builder.emitCmpRegReg(rax, rax, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, elseLabel);

    builder.emitOpBinaryRegImm(rsp, ApInt(40, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0, r10, MicroOpBits::B64);
    builder.emitCallReg(rax, CallConvKind::Host);
    builder.emitOpBinaryRegImm(rsp, ApInt(40, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

    builder.placeLabel(elseLabel);
    builder.emitOpBinaryRegImm(rsp, ApInt(56, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 8, r11, MicroOpBits::B64);
    builder.emitCallReg(rax, CallConvKind::Host);
    builder.emitOpBinaryRegImm(rsp, ApInt(56, 64), MicroOp::Add, MicroOpBits::B64);

    builder.placeLabel(doneLabel);
    builder.emitRet();

    SWC_RESULT_VERIFY(runStackAdjustNormalizePass(builder));

    const MicroOperandStorage& operands = builder.operands();

    uint32_t      stackAdjustCount = 0;
    MicroInstrRef firstAdjustRef   = MicroInstrRef::invalid();
    MicroInstrRef lastAdjustRef    = MicroInstrRef::invalid();
    MicroInstrRef retRef           = MicroInstrRef::invalid();
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        if (it->op == MicroInstrOpcode::Ret)
            retRef = it.current;

        const MicroInstrOperand* ops = it->ops(operands);
        if (!isStackAdjust(*it, ops, rsp, MicroOp::Subtract, 56) && !isStackAdjust(*it, ops, rsp, MicroOp::Add, 56))
            continue;

        if (firstAdjustRef.isInvalid())
            firstAdjustRef = it.current;
        lastAdjustRef = it.current;
        ++stackAdjustCount;
    }

    if (stackAdjustCount != 2)
        return Result::Error;
    if (firstAdjustRef.isInvalid() || lastAdjustRef.isInvalid() || retRef.isInvalid())
        return Result::Error;

    const MicroInstr* firstAdjust = builder.instructions().ptr(firstAdjustRef);
    const MicroInstr* lastAdjust  = builder.instructions().ptr(lastAdjustRef);
    if (!firstAdjust || !lastAdjust)
        return Result::Error;

    if (!isStackAdjust(*firstAdjust, firstAdjust->ops(operands), rsp, MicroOp::Subtract, 56))
        return Result::Error;
    if (!isStackAdjust(*lastAdjust, lastAdjust->ops(operands), rsp, MicroOp::Add, 56))
        return Result::Error;

    if (builder.instructions().findPreviousInstructionRef(retRef) != lastAdjustRef)
        return Result::Error;

    uint64_t thenStoreOffset = 0;
    uint64_t elseStoreOffset = 0;
    if (!findStoreOffsetForSourceReg(builder, r10, thenStoreOffset))
        return Result::Error;
    if (!findStoreOffsetForSourceReg(builder, r11, elseStoreOffset))
        return Result::Error;

    if (thenStoreOffset != 16)
        return Result::Error;
    if (elseStoreOffset != 8)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
