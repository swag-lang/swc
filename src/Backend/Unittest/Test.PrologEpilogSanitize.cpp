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
}

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_MergesAdjacentStackAdjustments)
{
    constexpr MicroReg RSP = MicroReg::intReg(4);
    constexpr MicroReg RBP = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(RBP);
    builder.emitLoadRegReg(RBP, RSP, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(RSP, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(RSP, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitNop();
    builder.emitOpBinaryRegImm(RSP, ApInt(24, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(RSP, ApInt(8, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPrologEpilogSanitizePass(builder));

    if (builder.instructions().count() != 6)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          subInst  = instructionAt(builder, 2);
    const MicroInstr*          addInst  = instructionAt(builder, 4);
    if (!subInst || !addInst)
        return Result::Error;

    if (!isStackAdjust(*subInst, subInst->ops(operands), RSP, MicroOp::Subtract, 48))
        return Result::Error;
    if (!isStackAdjust(*addInst, addInst->ops(operands), RSP, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPrologEpilogSanitize_DoesNotMergeOutsideEntryExitRegions)
{
    constexpr MicroReg RSP = MicroReg::intReg(4);
    constexpr MicroReg RBP = MicroReg::intReg(5);
    MicroBuilder       builder(ctx);

    builder.emitPush(RBP);
    builder.emitLoadRegReg(RBP, RSP, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(RSP, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitNop();
    builder.emitOpBinaryRegImm(RSP, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(RSP, ApInt(32, 64), MicroOp::Add, MicroOpBits::B64);
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

    if (!isStackAdjust(*firstSubInst, firstSubInst->ops(operands), RSP, MicroOp::Subtract, 16))
        return Result::Error;
    if (!isStackAdjust(*secondSubInst, secondSubInst->ops(operands), RSP, MicroOp::Subtract, 32))
        return Result::Error;
    if (!isStackAdjust(*epilogueAddIns, epilogueAddIns->ops(operands), RSP, MicroOp::Add, 32))
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
