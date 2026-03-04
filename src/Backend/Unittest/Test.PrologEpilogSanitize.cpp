#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PrologEpilogSanitize.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runPrologEpilogSanitizePass(MicroBuilder& builder)
    {
        MicroPrologEpilogSanitizePass pass;
        MicroPassManager              passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    const MicroInstr* instructionAt(const MicroBuilder& builder, uint32_t index)
    {
        uint32_t currentIndex = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (currentIndex == index)
                return &inst;
            ++currentIndex;
        }

        return nullptr;
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

    bool isFramePointerSetup(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg framePointer, MicroReg stackPointer)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                if (inst.numOperands < 3)
                    return false;
                return ops[0].reg == framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            case MicroInstrOpcode::LoadAddrRegMem:
                if (inst.numOperands < 4)
                    return false;
                return ops[0].reg == framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            default:
                return false;
        }
    }
}

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_MergesAdjacentStackAdjustments)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitNop();
    builder.emitOpBinaryRegImm(rsp, ApInt(24, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(8, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 6)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          subInst  = instructionAt(builder, 2);
    const MicroInstr*          addInst  = instructionAt(builder, 4);
    if (!subInst || !addInst)
        return Result::Error;

    if (!isStackAdjust(*subInst, subInst->ops(operands), rsp, MicroOp::Subtract, 48))
        return Result::Error;
    if (!isStackAdjust(*addInst, addInst->ops(operands), rsp, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_DoesNotMergeOutsideEntryExitRegions)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitNop();
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 7)
        return Result::Error;

    const MicroOperandStorage& operands       = builder.operands();
    const MicroInstr*          firstSubInst   = instructionAt(builder, 2);
    const MicroInstr*          secondSubInst  = instructionAt(builder, 4);
    const MicroInstr*          epilogueAddIns = instructionAt(builder, 5);
    if (!firstSubInst || !secondSubInst || !epilogueAddIns)
        return Result::Error;

    if (!isStackAdjust(*firstSubInst, firstSubInst->ops(operands), rsp, MicroOp::Subtract, 16))
        return Result::Error;
    if (!isStackAdjust(*secondSubInst, secondSubInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isStackAdjust(*epilogueAddIns, epilogueAddIns->ops(operands), rsp, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_KeepsOnlyLastFramePointerSetupInEntryProlog)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 4)
        return Result::Error;

    const MicroOperandStorage& operands   = builder.operands();
    const MicroInstr*          firstInst  = instructionAt(builder, 0);
    const MicroInstr*          secondInst = instructionAt(builder, 1);
    const MicroInstr*          thirdInst  = instructionAt(builder, 2);
    const MicroInstr*          fourthInst = instructionAt(builder, 3);
    if (!firstInst || !secondInst || !thirdInst || !fourthInst)
        return Result::Error;

    if (firstInst->op != MicroInstrOpcode::Push)
        return Result::Error;
    if (!isStackAdjust(*secondInst, secondInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isFramePointerSetup(*thirdInst, thirdInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (fourthInst->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_DoesNotTouchFramePointerSetupAfterBodyStarts)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitNop();
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 5)
        return Result::Error;

    const MicroOperandStorage& operands    = builder.operands();
    const MicroInstr*          firstSetup  = instructionAt(builder, 1);
    const MicroInstr*          secondSetup = instructionAt(builder, 3);
    if (!firstSetup || !secondSetup)
        return Result::Error;

    if (!isFramePointerSetup(*firstSetup, firstSetup->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isFramePointerSetup(*secondSetup, secondSetup->ops(operands), rbp, rsp))
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
