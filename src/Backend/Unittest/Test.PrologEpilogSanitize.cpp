#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PrologEpilogSanitize.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPrologEpilogSanitizePass(MicroBuilder& builder, const bool forceFramePointer = false)
    {
        MicroPrologEpilogSanitizePass pass;
        MicroPassManager              passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind      = CallConvKind::Host;
        passContext.forceFramePointer = forceFramePointer;
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

    bool isStackProbeLoad(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg probeReg, MicroReg stackPointer, uint64_t expectedOffset)
    {
        if (!ops)
            return false;
        if (inst.op != MicroInstrOpcode::LoadRegMem || inst.numOperands < 4)
            return false;
        if (ops[0].reg != probeReg)
            return false;
        if (ops[1].reg != stackPointer)
            return false;
        if (ops[2].opBits != MicroOpBits::B64)
            return false;
        if (ops[3].valueU64 != expectedOffset)
            return false;
        return true;
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

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 6)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          fpInst   = instructionAt(builder, 1);
    const MicroInstr*          subInst  = instructionAt(builder, 2);
    const MicroInstr*          addInst  = instructionAt(builder, 4);
    if (!subInst || !fpInst || !addInst)
        return Result::Error;

    if (!isFramePointerSetup(*fpInst, fpInst->ops(operands), rbp, rsp))
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

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 7)
        return Result::Error;

    const MicroOperandStorage& operands       = builder.operands();
    const MicroInstr*          fpInst         = instructionAt(builder, 1);
    const MicroInstr*          firstSubInst   = instructionAt(builder, 2);
    const MicroInstr*          secondSubInst  = instructionAt(builder, 4);
    const MicroInstr*          epilogueAddIns = instructionAt(builder, 5);
    if (!firstSubInst || !fpInst || !secondSubInst || !epilogueAddIns)
        return Result::Error;

    if (!isFramePointerSetup(*fpInst, fpInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isStackAdjust(*firstSubInst, firstSubInst->ops(operands), rsp, MicroOp::Subtract, 16))
        return Result::Error;
    if (!isStackAdjust(*secondSubInst, secondSubInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isStackAdjust(*epilogueAddIns, epilogueAddIns->ops(operands), rsp, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_ExpandsLargeWindowsStackAdjustIntoPageProbes)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(rsp, ApInt(12 * 1024, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 5)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          subInst  = instructionAt(builder, 0);
    const MicroInstr*          probe0   = instructionAt(builder, 1);
    const MicroInstr*          probe1   = instructionAt(builder, 2);
    const MicroInstr*          probe2   = instructionAt(builder, 3);
    const MicroInstr*          retInst  = instructionAt(builder, 4);
    if (!subInst || !probe0 || !probe1 || !probe2 || !retInst)
        return Result::Error;

    if (!isStackAdjust(*subInst, subInst->ops(operands), rsp, MicroOp::Subtract, 12 * 1024ull))
        return Result::Error;
    if (!isStackProbeLoad(*probe0, probe0->ops(operands), rax, rsp, 8 * 1024ull))
        return Result::Error;
    if (!isStackProbeLoad(*probe1, probe1->ops(operands), rax, rsp, 4 * 1024ull))
        return Result::Error;
    if (!isStackProbeLoad(*probe2, probe2->ops(operands), rax, rsp, 0))
        return Result::Error;
    if (retInst->op != MicroInstrOpcode::Ret)
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

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

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
    if (!isFramePointerSetup(*secondInst, secondInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isStackAdjust(*thirdInst, thirdInst->ops(operands), rsp, MicroOp::Subtract, 32))
        return Result::Error;
    if (fourthInst->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_ReinsertsForcedFramePointerSetupWhenMissing)
{
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rbp = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(rbp);
    builder.emitOpBinaryRegImm(rsp, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPrologEpilogSanitizePass(builder, true));

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
    if (!isFramePointerSetup(*secondInst, secondInst->ops(operands), rbp, rsp))
        return Result::Error;
    if (!isStackAdjust(*thirdInst, thirdInst->ops(operands), rsp, MicroOp::Subtract, 32))
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

    SWC_RESULT(runPrologEpilogSanitizePass(builder));

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

SWC_END_NAMESPACE();

#endif
