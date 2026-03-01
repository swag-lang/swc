#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runConstantPropagationPass(MicroBuilder& builder)
    {
        MicroConstantPropagationPass pass;
        MicroPassManager             passManager;
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
}

SWC_TEST_BEGIN(MicroConstantPropagation_RewritesLoadAndCompare)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r10 = MicroReg::intReg(10);

    builder.emitLoadRegImm(r8, ApInt(17, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(r9, r8, MicroOpBits::B64);
    builder.emitLoadRegImm(r10, ApInt(42, 64), MicroOpBits::B64);
    builder.emitCmpRegReg(r9, r10, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runConstantPropagationPass(builder));

    if (builder.instructions().count() != 4)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst1    = instructionAt(builder, 1);
    const MicroInstr*          inst3    = instructionAt(builder, 3);
    if (!inst1 || !inst3)
        return Result::Error;

    const MicroInstrOperand* ops1 = inst1->ops(operands);
    if (inst1->op != MicroInstrOpcode::LoadRegImm || ops1[2].valueU64 != 17)
        return Result::Error;

    const MicroInstrOperand* ops3 = inst3->ops(operands);
    if (inst3->op != MicroInstrOpcode::CmpRegImm || ops3[2].valueU64 != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroConstantPropagation_FoldsKnownBinaryOperation)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg r8 = MicroReg::intReg(8);
    constexpr MicroReg r9 = MicroReg::intReg(9);

    builder.emitLoadRegImm(r8, ApInt(2, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r9, ApInt(3, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(r8, r9, MicroOp::Add, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runConstantPropagationPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst2    = instructionAt(builder, 2);
    if (!inst2)
        return Result::Error;

    const MicroInstrOperand* ops2 = inst2->ops(operands);
    if (inst2->op != MicroInstrOpcode::LoadRegImm || ops2[2].valueU64 != 5)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroConstantPropagation_FoldsKnownSignAndZeroExtend)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r10 = MicroReg::intReg(10);

    builder.emitLoadRegImm(r8, ApInt(0xF6, 8), MicroOpBits::B8);
    builder.emitLoadSignedExtendRegReg(r9, r8, MicroOpBits::B64, MicroOpBits::B8);
    builder.emitLoadZeroExtendRegReg(r10, r8, MicroOpBits::B64, MicroOpBits::B8);

    SWC_RESULT_VERIFY(runConstantPropagationPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst1    = instructionAt(builder, 1);
    const MicroInstr*          inst2    = instructionAt(builder, 2);
    if (!inst1 || !inst2)
        return Result::Error;

    const MicroInstrOperand* ops1 = inst1->ops(operands);
    const MicroInstrOperand* ops2 = inst2->ops(operands);
    if (inst1->op != MicroInstrOpcode::LoadRegImm || ops1[2].valueU64 != 0xFFFFFFFFFFFFFFF6ull)
        return Result::Error;
    if (inst2->op != MicroInstrOpcode::LoadRegImm || ops2[2].valueU64 != 0xF6ull)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroConstantPropagation_ReadsSubRangeFromKnownStackSlot)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg stackPtr = MicroReg::intReg(4);
    constexpr MicroReg r8       = MicroReg::intReg(8);

    builder.emitLoadMemImm(stackPtr, 40, ApInt(0x1122334455667788ull, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(r8, stackPtr, 44, MicroOpBits::B32);

    SWC_RESULT_VERIFY(runConstantPropagationPass(builder));

    const MicroInstr* inst1 = instructionAt(builder, 1);
    if (!inst1)
        return Result::Error;

    const MicroInstrOperand* ops1 = inst1->ops(builder.operands());
    if (inst1->op != MicroInstrOpcode::LoadRegImm || ops1[2].valueU64 != 0x11223344ull)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroConstantPropagation_FoldsKnownStackSignExtendLoad)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg stackPtr = MicroReg::intReg(4);
    constexpr MicroReg r8       = MicroReg::intReg(8);

    builder.emitLoadMemImm(stackPtr, 16, ApInt(0xFFFFFFFEull, 32), MicroOpBits::B32);
    builder.emitLoadSignedExtendRegMem(r8, stackPtr, 16, MicroOpBits::B64, MicroOpBits::B32);

    SWC_RESULT_VERIFY(runConstantPropagationPass(builder));

    const MicroInstr* inst1 = instructionAt(builder, 1);
    if (!inst1)
        return Result::Error;

    const MicroInstrOperand* ops1 = inst1->ops(builder.operands());
    if (inst1->op != MicroInstrOpcode::LoadRegImm || ops1[2].valueU64 != 0xFFFFFFFFFFFFFFFEull)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroConstantPropagation_FoldsKnownIndexedStackLoad)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg stackPtr = MicroReg::intReg(4);
    constexpr MicroReg idxReg   = MicroReg::intReg(9);
    constexpr MicroReg dstReg   = MicroReg::intReg(10);

    builder.emitLoadRegImm(idxReg, ApInt(2, 64), MicroOpBits::B64);
    builder.emitLoadMemImm(stackPtr, 24, ApInt(0x1234, 32), MicroOpBits::B32);
    builder.emitLoadAmcRegMem(dstReg, MicroOpBits::B32, stackPtr, idxReg, 4, 16, MicroOpBits::B32);

    SWC_RESULT_VERIFY(runConstantPropagationPass(builder));

    const MicroInstr* inst2 = instructionAt(builder, 2);
    if (!inst2)
        return Result::Error;

    const MicroInstrOperand* ops2 = inst2->ops(builder.operands());
    if (inst2->op != MicroInstrOpcode::LoadRegImm || ops2[2].valueU64 != 0x1234ull)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
