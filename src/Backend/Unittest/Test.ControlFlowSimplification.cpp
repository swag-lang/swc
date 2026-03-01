#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ControlFlowSimplification.h"
#include "Support/Unittest/Unittest.h"
#include "Backend/Micro/MicroPassContext.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runControlFlowSimplificationPass(MicroBuilder& builder)
    {
        MicroControlFlowSimplificationPass pass;
        MicroPassManager                   passManager;
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

SWC_TEST_BEGIN(MicroControlFlowSimplification_RemovesRedundantFlow)
{
    MicroBuilder        builder(ctx);
    constexpr MicroReg  r8        = MicroReg::intReg(8);
    constexpr MicroReg  r9        = MicroReg::intReg(9);
    const MicroLabelRef bodyLabel = builder.createLabel();
    const MicroLabelRef deadLabel = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, bodyLabel);
    builder.placeLabel(bodyLabel);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();
    builder.emitLoadRegImm(r9, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(deadLabel);

    SWC_RESULT_VERIFY(runControlFlowSimplificationPass(builder));

    if (builder.instructions().count() != 2)
        return Result::Error;

    const MicroInstr* inst0 = instructionAt(builder, 0);
    const MicroInstr* inst1 = instructionAt(builder, 1);
    if (!inst0 || !inst1)
        return Result::Error;

    if (inst0->op != MicroInstrOpcode::LoadRegImm || inst1->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroControlFlowSimplification_MergesJumpChain)
{
    MicroBuilder        builder(ctx);
    constexpr MicroReg  r8             = MicroReg::intReg(8);
    const MicroLabelRef fallthroughRef = builder.createLabel();
    const MicroLabelRef targetRef      = builder.createLabel();

    builder.emitCmpRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, fallthroughRef);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, targetRef);
    builder.placeLabel(fallthroughRef);
    builder.emitRet();
    builder.placeLabel(targetRef);
    builder.emitRet();

    SWC_RESULT_VERIFY(runControlFlowSimplificationPass(builder));

    uint32_t jumpCount = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::JumpCond)
            continue;

        ++jumpCount;
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (!ops)
            return Result::Error;

        if (ops[0].cpuCond != MicroCond::NotEqual)
            return Result::Error;
        if (ops[2].valueU64 != targetRef.get())
            return Result::Error;
    }

    if (jumpCount != 1)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
